defmodule Yargy.Grammar do
  @moduledoc """
  Declarative grammar DSL for token-level Earley parsing.

  Provides a NimbleParsec-inspired API for building Yargy grammars
  with morphological token predicates. Rules and parsers are built
  lazily on first access and cached in `persistent_term`.

  ## Usage

      defmodule MyApp.PersonGrammar do
        use Yargy.Grammar

        defrule :surname, gram("Surn") ~> capitalized()
        defrule :first_name, gram("Name") ~> capitalized()
        defrule :patronymic, gram("Patr") ~> capitalized()
        defrule :dot, token(".")
        defrule :initial, upper() ~> length_eq(1)
        defrule :initial_dot, rule(:initial) ~> rule(:dot)

        defgrammar :person, choice([
          rule(:surname) ~> rule(:first_name) ~> optional(rule(:patronymic)),
          rule(:first_name) ~> optional(rule(:patronymic)) ~> rule(:surname),
          rule(:surname) ~> rule(:initial_dot) ~> rule(:initial_dot),
          rule(:initial_dot) ~> rule(:initial_dot) ~> rule(:surname)
        ])
      end

      MyApp.PersonGrammar.person(tokens)
      #=> [%Parser.Match{...}, ...]

  ## Terminal predicates

  - `token(value)` — exact value match
  - `token(values)` — value in list
  - `lemma(word)` — normalized form match (via MorphRu)
  - `lemma(words)` — lemma in list
  - `gram(grammeme)` — has OpenCorpora grammeme
  - `integer()` — token type `:int`
  - `word()` — token type `:word`
  - `punct(value)` — punctuation with exact value
  - `capitalized()` — first char uppercase
  - `upper()` — all chars uppercase
  - `lower()` — all chars lowercase
  - `length_eq(n)` — value length
  - `gte(n)` / `lte(n)` — integer bounds
  - `caseless(value)` — case-insensitive match
  - `pred(fun)` — custom predicate function

  ## Composition

  - `a ~> b` — sequence (left to right)
  - `choice([a, b, c])` — alternation
  - `optional(a)` — zero or one
  - `repeat(a)` — one or more
  - `repeat(a, min: 2, max: 5)` — bounded repetition
  - `rule(:name)` — reference a named `defrule`

  ## Macros

  - `defrule :name, combinator` — named reusable sub-rule
  - `defgrammar :name, combinator` — public parser with generated functions
  """

  alias Yargy.{Predicate, Rule}

  # --- Combinator constructors ---
  # These return plain tuples (serializable, no closures — except `pred`).

  def token(value) when is_binary(value), do: {:terminal, {:eq, value}}
  def token(values) when is_list(values), do: {:terminal, {:in, values}}

  def lemma(word) when is_binary(word), do: {:terminal, {:normalized, word}}
  def lemma(words) when is_list(words), do: {:terminal, {:normalized_in, words}}

  def gram(grammeme), do: {:terminal, {:gram, grammeme}}

  def integer, do: {:terminal, {:type, :int}}
  def word, do: {:terminal, {:type, :word}}
  def punct(value), do: {:terminal, {:punct, value}}

  def capitalized, do: {:terminal, :capitalized}
  def upper, do: {:terminal, :upper}
  def lower, do: {:terminal, :lower}
  def length_eq(n), do: {:terminal, {:length_eq, n}}
  def gte(n), do: {:terminal, {:gte, n}}
  def lte(n), do: {:terminal, {:lte, n}}
  def caseless(value) when is_binary(value), do: {:terminal, {:caseless, value}}
  def caseless(values) when is_list(values), do: {:terminal, {:in_caseless, values}}
  @doc "All predicates must match the same token (logical AND)."
  def all(predicates) when is_list(predicates), do: {:terminal, {:all, predicates}}

  @doc "Any predicate matches the token (logical OR on a single token)."
  def any(predicates) when is_list(predicates), do: {:terminal, {:any, predicates}}

  def pred(fun) when is_function(fun, 1), do: {:terminal, {:custom, fun}}

  def rule(name) when is_atom(name), do: {:ref, name}
  def choice(alternatives) when is_list(alternatives), do: {:choice, alternatives}
  def optional(combinator), do: {:optional, combinator}
  def repeat(combinator, opts \\ []), do: {:repeat, combinator, opts}

  # --- Match combinators (bag-of-features, not sequential) ---

  @doc "At least one token matches the predicate."
  def any_token(terminal), do: {:match, :any_token, terminal}
  @doc "No token matches the predicate."
  def no_token(terminal), do: {:match, :no_token, terminal}
  @doc "First word token matches the predicate."
  def first_token(terminal), do: {:match, :first_token, terminal}
  @doc "All conditions must hold (logical AND over match conditions)."
  def all_of(conditions) when is_list(conditions), do: {:match, :all_of, conditions}
  @doc "At least one condition must hold (logical OR over match conditions)."
  def any_of(conditions) when is_list(conditions), do: {:match, :any_of, conditions}
  @doc "At most `n` word tokens in the sentence."
  def max_words(n) when is_integer(n), do: {:match, :max_words, n}

  def sequence(left, right) do
    left_items = unwrap_sequence(left)
    right_items = unwrap_sequence(right)
    {:sequence, left_items ++ right_items}
  end

  defp unwrap_sequence({:sequence, items}), do: items
  defp unwrap_sequence(other), do: [other]

  # --- Compilation: combinator tuple → %Rule{} ---

  @doc false
  def build_rule(combinator, name, rule_map) do
    rule = to_rule(combinator, rule_map)
    Rule.named(rule, to_string(name))
  end

  @doc false
  def ensure_initialized(module) do
    key = {module, :yargy_initialized}

    case :persistent_term.get(key, false) do
      true -> :ok
      false ->
        module.__yargy_init__()
        :persistent_term.put(key, true)
        :ok
    end
  end

  defp to_rule({:terminal, spec}, _rule_map) do
    Rule.rule([to_predicate(spec)])
  end

  defp to_rule({:sequence, items}, rule_map) do
    terms = Enum.map(items, &to_term(&1, rule_map))
    Rule.rule([terms])
  end

  defp to_rule({:choice, alternatives}, rule_map) do
    rules = Enum.map(alternatives, &to_rule(&1, rule_map))
    Rule.or_rule(rules)
  end

  defp to_rule({:optional, inner}, rule_map) do
    Rule.optional(to_rule(inner, rule_map))
  end

  defp to_rule({:repeat, inner, opts}, rule_map) do
    Rule.repeatable(to_rule(inner, rule_map), opts)
  end

  defp to_rule({:ref, name}, rule_map) do
    case Map.fetch(rule_map, name) do
      {:ok, rule} -> rule
      :error -> raise ArgumentError, "undefined rule #{inspect(name)}"
    end
  end

  defp to_term({:terminal, spec}, _), do: to_predicate(spec)
  defp to_term({:ref, name}, rule_map), do: Map.fetch!(rule_map, name)
  defp to_term(other, rule_map), do: to_rule(other, rule_map)

  defp to_predicate({:eq, v}), do: Predicate.eq(v)
  defp to_predicate({:in, vs}), do: Predicate.in_(vs)
  defp to_predicate({:normalized, w}), do: Predicate.normalized(w)
  defp to_predicate({:normalized_in, ws}), do: Predicate.normalized_in(ws)
  defp to_predicate({:gram, g}), do: Predicate.gram(g)
  defp to_predicate({:type, t}), do: Predicate.type(t)
  defp to_predicate({:punct, v}), do: Predicate.and_(Predicate.type(:punct), Predicate.eq(v))
  defp to_predicate(:capitalized), do: Predicate.capitalized?()
  defp to_predicate(:upper), do: Predicate.upper?()
  defp to_predicate(:lower), do: Predicate.lower?()
  defp to_predicate({:length_eq, n}), do: Predicate.length_eq(n)
  defp to_predicate({:gte, n}), do: Predicate.gte(n)
  defp to_predicate({:lte, n}), do: Predicate.lte(n)
  defp to_predicate({:caseless, v}), do: Predicate.caseless(v)
  defp to_predicate({:in_caseless, vs}), do: Predicate.in_caseless(vs)
  defp to_predicate({:custom, fun}), do: fun

  defp to_predicate({:all, predicates}) do
    fns = Enum.map(predicates, fn {:terminal, spec} -> to_predicate(spec) end)
    Predicate.and_(fns)
  end

  defp to_predicate({:any, predicates}) do
    fns = Enum.map(predicates, fn {:terminal, spec} -> to_predicate(spec) end)
    Predicate.or_(fns)
  end

  # --- Match compilation: match combinator → (tokens -> boolean) ---

  @doc false
  def build_matcher(match_spec) do
    compile_match(match_spec)
  end

  defp compile_match({:match, :any_token, terminal}) do
    pred_fn = to_predicate(unwrap_terminal(terminal))
    fn tokens -> Enum.any?(tokens, pred_fn) end
  end

  defp compile_match({:match, :no_token, terminal}) do
    pred_fn = to_predicate(unwrap_terminal(terminal))
    fn tokens -> not Enum.any?(tokens, pred_fn) end
  end

  defp compile_match({:match, :first_token, terminal}) do
    pred_fn = to_predicate(unwrap_terminal(terminal))

    fn tokens ->
      case Enum.find(tokens, &(&1.type == :word)) do
        nil -> false
        token -> pred_fn.(token)
      end
    end
  end

  defp compile_match({:match, :all_of, conditions}) do
    matchers = Enum.map(conditions, &compile_match/1)
    fn tokens -> Enum.all?(matchers, fn m -> m.(tokens) end) end
  end

  defp compile_match({:match, :any_of, conditions}) do
    matchers = Enum.map(conditions, &compile_match/1)
    fn tokens -> Enum.any?(matchers, fn m -> m.(tokens) end) end
  end

  defp compile_match({:match, :max_words, n}) do
    fn tokens ->
      Enum.count(tokens, &(&1.type == :word)) <= n
    end
  end

  defp unwrap_terminal({:terminal, spec}), do: spec
  defp unwrap_terminal(other), do: other

  # --- Macros ---

  defmacro __using__(_opts) do
    quote do
      import Yargy.Grammar,
        only: [
          token: 1, lemma: 1, gram: 1, integer: 0, word: 0, punct: 1,
          capitalized: 0, upper: 0, lower: 0, length_eq: 1, gte: 1, lte: 1,
          caseless: 1, all: 1, any: 1, pred: 1, rule: 1, choice: 1, optional: 1,
          repeat: 1, repeat: 2, defrule: 2, defgrammar: 2,
          any_token: 1, no_token: 1, first_token: 1, all_of: 1, any_of: 1,
          max_words: 1, defmatch: 2
        ]

      import Yargy.Grammar.Operators, only: [~>: 2]

      Module.register_attribute(__MODULE__, :yargy_rules, accumulate: true)
      Module.register_attribute(__MODULE__, :yargy_grammars, accumulate: true)
      Module.register_attribute(__MODULE__, :yargy_matchers, accumulate: true)

      @before_compile Yargy.Grammar
    end
  end

  defmacro defrule(name, combinator) do
    # Store the combinator AST (not the evaluated value) so it can be
    # re-evaluated in __yargy_init__/0 at runtime.
    escaped_combinator = Macro.escape(combinator)

    quote do
      @yargy_rules %{name: unquote(name), combinator_ast: unquote(escaped_combinator)}
    end
  end

  defmacro defgrammar(name, combinator) do
    escaped_combinator = Macro.escape(combinator)

    quote do
      @yargy_grammars %{name: unquote(name), combinator_ast: unquote(escaped_combinator)}
    end
  end

  @doc """
  Defines a bag-of-features matcher — checks unordered token presence.

  Generates `name?(tokens)` and `name_match?(text)` functions.

  ## Example

      defmatch :evidence, all_of([
        any_token(lemma(~w[подтверждаться подтвердить])),
        any_token(lemma(~w[акт квитанция чек выписка]))
      ])

      # Generates:
      # evidence?(tokens) :: boolean
      # evidence_match?(text) :: boolean
  """
  defmacro defmatch(name, match_spec) do
    escaped_spec = Macro.escape(match_spec)

    quote do
      @yargy_matchers %{name: unquote(name), match_ast: unquote(escaped_spec)}
    end
  end

  defmacro __before_compile__(env) do
    rules_raw = Module.get_attribute(env.module, :yargy_rules) |> Enum.reverse()
    grammars_raw = Module.get_attribute(env.module, :yargy_grammars) |> Enum.reverse()
    matchers_raw = Module.get_attribute(env.module, :yargy_matchers) |> Enum.reverse()

    # Generate __yargy_init__/0 that rebuilds all rules and parsers.
    # Combinator ASTs are unquoted here, so `pred(fn ... end)` closures are
    # re-created as real code — no Macro.escape of functions needed.

    init_body =
      Enum.map(rules_raw, fn %{name: name, combinator_ast: combinator_ast} ->
        pt_key = Macro.escape({env.module, :yargy_rule, name})

        quote do
          compiled = Yargy.Grammar.build_rule(unquote(combinator_ast), unquote(name), rule_map)
          :persistent_term.put(unquote(pt_key), compiled)
          rule_map = Map.put(rule_map, unquote(name), compiled)
        end
      end)

    init_grammars =
      Enum.map(grammars_raw, fn %{name: name, combinator_ast: combinator_ast} ->
        pt_key = Macro.escape({env.module, :yargy_parser, name})

        quote do
          compiled = Yargy.Grammar.build_rule(unquote(combinator_ast), unquote(name), rule_map)
          parser = Yargy.Parser.new(compiled)
          :persistent_term.put(unquote(pt_key), parser)
        end
      end)

    rule_fns =
      Enum.map(rules_raw, fn %{name: name} ->
        pt_key = Macro.escape({env.module, :yargy_rule, name})

        quote do
          @doc false
          def unquote(:"#{name}_rule")() do
            Yargy.Grammar.ensure_initialized(__MODULE__)
            :persistent_term.get(unquote(pt_key))
          end
        end
      end)

    grammar_fns =
      Enum.map(grammars_raw, fn %{name: name} ->
        pt_key = Macro.escape({env.module, :yargy_parser, name})

        quote do
          @doc "Returns the pre-built parser for `#{unquote(name)}`."
          def unquote(:"#{name}_parser")() do
            Yargy.Grammar.ensure_initialized(__MODULE__)
            :persistent_term.get(unquote(pt_key))
          end

          @doc "Finds all matches of `#{unquote(name)}` in morph-tagged tokens."
          def unquote(name)(tokens) when is_list(tokens) do
            Yargy.Parser.findall(unquote(:"#{name}_parser")(), tokens)
          end

          @doc "Finds all matches of `#{unquote(name)}` in raw text."
          def unquote(:"#{name}_text")(text) when is_binary(text) do
            tokens = Yargy.Pipeline.morph_tokenize(text)
            unquote(name)(tokens)
          end
        end
      end)

    init_matchers =
      Enum.map(matchers_raw, fn %{name: name, match_ast: match_ast} ->
        pt_key = Macro.escape({env.module, :yargy_matcher, name})

        quote do
          matcher = Yargy.Grammar.build_matcher(unquote(match_ast))
          :persistent_term.put(unquote(pt_key), matcher)
        end
      end)

    matcher_fns =
      Enum.map(matchers_raw, fn %{name: name} ->
        pt_key = Macro.escape({env.module, :yargy_matcher, name})

        quote do
          @doc "Checks if morph-tagged tokens match the `#{unquote(name)}` pattern."
          def unquote(:"#{name}?")(tokens) when is_list(tokens) do
            Yargy.Grammar.ensure_initialized(__MODULE__)
            matcher = :persistent_term.get(unquote(pt_key))
            matcher.(tokens)
          end

          @doc "Checks if raw text matches the `#{unquote(name)}` pattern."
          def unquote(:"#{name}_match?")(text) when is_binary(text) do
            tokens = Yargy.Pipeline.morph_tokenize(text)
            unquote(:"#{name}?")(tokens)
          end
        end
      end)

    quote do
      @doc false
      def __yargy_init__ do
        import Yargy.Grammar,
          only: [
            token: 1, lemma: 1, gram: 1, integer: 0, word: 0, punct: 1,
            capitalized: 0, upper: 0, lower: 0, length_eq: 1, gte: 1, lte: 1,
            caseless: 1, all: 1, any: 1, pred: 1, rule: 1, choice: 1, optional: 1,
            repeat: 1, repeat: 2, any_token: 1, no_token: 1, first_token: 1,
            all_of: 1, any_of: 1, max_words: 1
          ]

        import Yargy.Grammar.Operators, only: [~>: 2]

        rule_map = %{}
        unquote_splicing(init_body)
        unquote_splicing(init_grammars)
        unquote_splicing(init_matchers)
        :ok
      end

      unquote_splicing(rule_fns)
      unquote_splicing(grammar_fns)
      unquote_splicing(matcher_fns)
    end
  end
end

defmodule Yargy.Grammar.Operators do
  @moduledoc """
  The `~>` operator for sequencing grammar combinators.

      gram("Surn") ~> capitalized()
  """

  defmacro left ~> right do
    quote do
      Yargy.Grammar.sequence(unquote(left), unquote(right))
    end
  end
end
