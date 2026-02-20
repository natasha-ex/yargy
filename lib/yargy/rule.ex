defmodule Yargy.Rule do
  @moduledoc """
  Grammar rules for the Earley parser.

  A rule has a name (or auto-generated ID), a list of productions,
  and optional interpretation metadata.

  A production is a sequence of terms. Each term is either:
  - A predicate (matches a token)
  - Another rule (non-terminal)

  Rules support:
  - `optional/1` — zero or one occurrences
  - `repeatable/1` — one or more occurrences
  - `repeatable/2` — bounded repeatable with min/max
  - `named/2` — gives the rule a name for debugging
  - `interpretation/2` — attaches fact extraction metadata
  - `forward/0` + `define/2` — forward references for recursive grammars
  """

  defmodule Production do
    @moduledoc "A single alternative in a rule — a sequence of terms."

    defstruct terms: [], main: 0

    @type grammar_term :: (Yargy.Token.t() -> boolean()) | Yargy.Rule.t()
    @type t :: %__MODULE__{terms: [grammar_term()], main: non_neg_integer()}

    def new(terms, main \\ 0) do
      %__MODULE__{terms: terms, main: main}
    end
  end

  defstruct [:name, :interpretator, :relation, productions: []]

  @type t :: %__MODULE__{
          name: String.t() | nil,
          productions: [Production.t()],
          interpretator: term() | nil,
          relation: term() | nil
        }

  @doc "Creates a rule from one or more sequences of terms (alternatives)."
  def rule(terms) when is_list(terms) do
    case terms do
      [first | _] when is_list(first) ->
        %__MODULE__{productions: Enum.map(terms, &Production.new/1)}

      _ ->
        %__MODULE__{productions: [Production.new(terms)]}
    end
  end

  @doc "Creates an OR rule (multiple alternatives)."
  def or_rule(rules) when is_list(rules) do
    productions =
      Enum.flat_map(rules, fn
        %__MODULE__{} = r -> r.productions
        production -> [Production.new(List.wrap(production))]
      end)

    %__MODULE__{productions: productions}
  end

  @doc "Makes a rule optional (matches zero or one time)."
  def optional(%__MODULE__{} = rule) do
    %{rule | productions: rule.productions ++ [Production.new([])]}
  end

  @doc """
  Makes a rule repeatable.

  - `repeatable(rule)` — one or more (unbounded)
  - `repeatable(rule, min: 2)` — at least 2
  - `repeatable(rule, max: 3)` — at most 3
  - `repeatable(rule, min: 2, max: 4)` — between 2 and 4
  """
  def repeatable(%__MODULE__{} = rule, opts \\ []) do
    min = Keyword.get(opts, :min, 1)
    max = Keyword.get(opts, :max, :infinity)

    if min < 0, do: raise(ArgumentError, "min must be non-negative")
    if max != :infinity and max < 1, do: raise(ArgumentError, "max must be >= 1")
    if max != :infinity and min > max, do: raise(ArgumentError, "min must be <= max")

    case {min, max} do
      {1, :infinity} -> unbounded_repeatable(rule)
      {_, _} -> bounded_repeatable(rule, min, max)
    end
  end

  defp unbounded_repeatable(rule) do
    fwd = forward()

    repeat_productions =
      Enum.map(rule.productions, fn prod ->
        Production.new(prod.terms ++ [fwd])
      end)

    all_prods = rule.productions ++ repeat_productions
    define(fwd, %{rule | productions: all_prods})
  end

  defp bounded_repeatable(rule, min, max) do
    base_prods = rule.productions

    if min > 1 do
      prefix = build_prefix_terms(base_prods, min - 1)
      tail_count = if max == :infinity, do: :infinity, else: max - min + 1
      tail = build_tail(rule, base_prods, tail_count)

      %__MODULE__{
        productions: [Production.new(prefix ++ [tail])]
      }
    else
      build_tail(rule, base_prods, max)
    end
  end

  defp build_prefix_terms(base_prods, n) do
    base = hd(base_prods)
    List.duplicate(base.terms, n) |> List.flatten()
  end

  defp build_tail(_rule, base_prods, :infinity) do
    tail = %__MODULE__{productions: base_prods}
    unbounded_repeatable(tail)
  end

  defp build_tail(_rule, base_prods, 1) do
    %__MODULE__{productions: base_prods}
  end

  defp build_tail(rule, base_prods, remaining) when is_integer(remaining) and remaining > 1 do
    inner = build_tail(rule, base_prods, remaining - 1)

    chain_prods =
      for prod <- base_prods do
        Production.new(prod.terms ++ [inner])
      end

    %__MODULE__{productions: base_prods ++ chain_prods}
  end

  @doc """
  Creates a forward reference placeholder for recursive grammars.

  Returns a rule whose productions will be set later via `define/2`.
  Uses `:persistent_term` so the parser sees the updated productions.
  """
  def forward do
    ref = :erlang.make_ref()
    %__MODULE__{name: {:forward, ref}, productions: []}
  end

  @doc "Defines a forward reference's actual rule."
  def define(%__MODULE__{name: {:forward, ref}} = fwd, %__MODULE__{} = target) do
    :persistent_term.put({__MODULE__, ref}, target.productions)
    %{fwd | productions: target.productions, name: target.name}
  end

  @doc false
  def resolve_forward(%__MODULE__{name: {:forward, ref}} = rule) do
    case :persistent_term.get({__MODULE__, ref}, nil) do
      nil -> rule
      prods -> %{rule | productions: prods}
    end
  end

  def resolve_forward(other), do: other

  @doc "Gives a rule a name for debugging and BNF output."
  def named(%__MODULE__{} = rule, name) do
    %{rule | name: name}
  end

  @doc "Attaches interpretation metadata to a rule."
  def interpretation(%__MODULE__{} = rule, interpretator) do
    %{rule | interpretator: interpretator}
  end

  @doc "Attaches a relation to a rule for grammatical agreement checking."
  def match(%__MODULE__{} = rule, relation) do
    %{rule | relation: relation}
  end

  @doc "Checks if a term is a rule (non-terminal) vs a predicate (terminal)."
  def non_terminal?(%__MODULE__{}), do: true
  def non_terminal?(_), do: false
end
