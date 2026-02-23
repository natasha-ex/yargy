defmodule Yargy.Parser do
  @moduledoc """
  Earley parser for grammar-based fact extraction.

  Port of Yargy's parser. The Earley algorithm processes tokens left-to-right,
  maintaining a chart of states. Each state tracks:
  - Which rule and production it belongs to
  - How far through the production it has progressed (dot position)
  - Where in the input it started

  Three operations:
  - PREDICT: when the dot is before a non-terminal, add states for that rule's productions
  - SCAN: when the dot is before a terminal (predicate), advance if the next token matches
  - COMPLETE: when a state is finished, advance all parent states that were waiting for this rule
  """

  alias Yargy.Rule

  defmodule State do
    @moduledoc false

    @enforce_keys [:rule, :rule_id, :production, :prod_id, :terms, :term_count, :dot, :start, :stop]
    defstruct [
      :rule, :rule_id, :production, :prod_id,
      :terms, :term_count,
      :dot, :start, :stop,
      children: []
    ]

    def new(rule, rule_id, production, prod_id, opts \\ []) do
      terms = List.to_tuple(production.terms)
      dot = opts[:dot] || 0
      %__MODULE__{
        rule: rule,
        rule_id: rule_id,
        production: production,
        prod_id: prod_id,
        terms: terms,
        term_count: tuple_size(terms),
        dot: dot,
        start: opts[:start] || 0,
        stop: opts[:stop] || 0,
        children: opts[:children] || []
      }
    end

    def completed?(%__MODULE__{dot: dot, term_count: tc}), do: dot >= tc

    def next_term(%__MODULE__{dot: dot, terms: terms}), do: elem(terms, dot)

    def advance(%__MODULE__{} = state, stop, child) do
      %{state | dot: state.dot + 1, stop: stop, children: [child | state.children]}
    end

    def key(%__MODULE__{prod_id: prod_id, dot: dot, start: start, stop: stop}) do
      {prod_id, dot, start, stop}
    end
  end

  defmodule Column do
    @moduledoc false

    defstruct [:index, :token, states: nil, count: 0, seen: %{}, waiting: %{}, predicted: %{}]

    def new(index, token \\ nil) do
      %__MODULE__{index: index, token: token, states: :array.new(default: nil)}
    end

    def add(%__MODULE__{} = col, %State{} = state) do
      key = State.key(state)

      case col.seen do
        %{^key => _} ->
          col

        _ ->
          col = %{
            col
            | states: :array.set(col.count, state, col.states),
              count: col.count + 1,
              seen: Map.put(col.seen, key, true)
          }

          update_waiting_index(col, state)
      end
    end

    def get_state(%__MODULE__{} = col, index) do
      :array.get(index, col.states)
    end

    def all_states(%__MODULE__{count: count, states: states}) do
      for i <- 0..(count - 1), do: :array.get(i, states)
    end

    defp update_waiting_index(col, state) do
      if State.completed?(state) do
        col
      else
        next = State.next_term(state)

        if Rule.non_terminal?(next) do
          rule_id = :erlang.phash2(next)
          existing = Map.get(col.waiting, rule_id, [])
          %{col | waiting: Map.put(col.waiting, rule_id, [state | existing])}
        else
          col
        end
      end
    end

    def waiting_for(%__MODULE__{waiting: waiting}, rule_id) do
      Map.get(waiting, rule_id, [])
    end
  end

  defmodule Match do
    @moduledoc "A successful parse match with tokens and span."

    alias Yargy.Interpretation.Interpreter
    alias Yargy.Relations

    defstruct [:rule, :tokens, :start, :stop, :children]

    def new(state, token_array) do
      tokens =
        if state.start >= state.stop do
          []
        else
          for i <- state.start..(state.stop - 1), do: elem(token_array, i)
        end

      %__MODULE__{
        rule: state.rule,
        tokens: tokens,
        start: state.start,
        stop: state.stop,
        children: Enum.reverse(state.children)
      }
    end

    def span(%__MODULE__{tokens: []}), do: {0, 0}

    def span(%__MODULE__{tokens: tokens}) do
      first = hd(tokens)
      last = List.last(tokens)
      {first.start, last.stop}
    end

    def text(%__MODULE__{tokens: tokens}) do
      Enum.map_join(tokens, " ", & &1.value)
    end

    @doc "Builds a parse tree from the match."
    def tree(%__MODULE__{rule: rule, children: children}) do
      {:node, rule_meta(rule), Enum.map(children, &build_tree/1)}
    end

    @doc "Extracts a structured fact from the match via interpretation."
    def fact(%__MODULE__{} = match) do
      tree = tree(match)
      Interpreter.interpret(tree)
    end

    @doc "Checks if all relation constraints in the match are satisfied."
    def valid_relations?(%__MODULE__{} = match) do
      tree = tree(match)
      pairs = collect_relation_pairs(tree)

      if pairs == [] do
        true
      else
        Relations.validate_match(pairs)
      end
    end

    defp collect_relation_pairs({:leaf, _token}), do: []

    defp collect_relation_pairs({:node, meta, children}) do
      own_pairs =
        case meta[:relation] do
          nil ->
            []

          relation ->
            main_token = find_main_token(children)
            if main_token, do: [{relation, main_token}], else: []
        end

      child_pairs = Enum.flat_map(children, &collect_relation_pairs/1)
      own_pairs ++ child_pairs
    end

    defp find_main_token([{:leaf, token} | _]), do: token
    defp find_main_token([{:node, _meta, children} | _]), do: find_main_token(children)
    defp find_main_token([]), do: nil

    defp build_tree({:leaf, token}), do: {:leaf, token}

    defp build_tree({:node, completed_state}) do
      children = Enum.reverse(completed_state.children)
      {:node, rule_meta(completed_state.rule), Enum.map(children, &build_tree/1)}
    end

    defp rule_meta(rule) do
      meta = %{name: rule.name}

      meta =
        if rule.interpretator, do: Map.put(meta, :interpretation, rule.interpretator), else: meta

      if rule.relation, do: Map.put(meta, :relation, rule.relation), else: meta
    end
  end

  @doc "Creates a new parser for the given rule."
  def new(%Rule{} = rule) do
    %{rule: rule}
  end

  @doc """
  Finds all non-overlapping matches of the rule in the token list.
  Returns matches sorted by position, with overlaps resolved
  (longer match wins, earlier match wins on tie).
  """
  def findall(%{rule: rule}, tokens) when is_list(tokens) do
    token_array = List.to_tuple(tokens)
    chart = parse(rule, token_array)

    matches =
      chart
      |> completed_states(rule)
      |> Enum.map(&Match.new(&1, token_array))
      |> Enum.filter(&Match.valid_relations?/1)
      |> Enum.sort_by(fn m -> {m.start, -(m.stop - m.start)} end)

    resolve_overlaps(matches)
  end

  @doc "Finds the first match."
  def find(parser, tokens) do
    case findall(parser, tokens) do
      [match | _] -> match
      [] -> nil
    end
  end

  @doc """
  Finds partial (incomplete) matches at the end of input.

  When the input ends mid-parse, the Earley chart's last column contains
  incomplete states — rules that matched some tokens but still expect more.
  This is useful for autocomplete: you can tell what grammar the user is
  in the middle of typing and how far they've gotten.

  Returns a list of `%{rule_name, matched_tokens, matched_text, start, dot,
  production_length, progress}` maps sorted by progress (most advanced first),
  deduplicated by rule name.

  ## Examples

      iex> rule = Rule.rule([[Predicate.eq("ст"), Predicate.eq("."), Predicate.type(:int)]])
      iex> parser = Parser.new(rule)
      iex> [partial] = Parser.partial_matches(parser, Tokenizer.tokenize("ст."))
      iex> partial.dot
      2
      iex> partial.production_length
      3
  """
  def partial_matches(%{rule: rule}, tokens) when is_list(tokens) do
    partial_matches(rule, tokens)
  end

  def partial_matches(%Rule{} = rule, tokens) when is_list(tokens) do
    token_array = List.to_tuple(tokens)
    chart = parse(rule, token_array)
    last_col = :array.get(:array.size(chart) - 1, chart)
    chart_size = :array.size(chart)

    last_col
    |> Column.all_states()
    |> Enum.reject(&State.completed?/1)
    |> Enum.filter(fn state -> state.dot > 0 end)
    |> Enum.map(fn state ->
      matched =
        if state.start <= chart_size - 2 do
          for i <- state.start..(chart_size - 2), do: elem(token_array, i)
        else
          []
        end

      %{
        rule_name: rule_label(state.rule),
        dot: state.dot,
        production_length: state.term_count,
        start: state.start,
        matched_tokens: Enum.map(matched, & &1.value),
        matched_text: Enum.map_join(matched, " ", & &1.value),
        progress: state.dot / max(state.term_count, 1)
      }
    end)
    |> Enum.sort_by(& &1.progress, :desc)
    |> Enum.uniq_by(& &1.rule_name)
  end

  defp rule_label(%Rule{name: name}) when is_binary(name), do: name
  defp rule_label(%Rule{name: {:forward, name}}), do: name
  defp rule_label(%Rule{name: nil}), do: nil
  defp rule_label(%Rule{name: name}), do: inspect(name)

  defp parse(rule, token_array) do
    size = tuple_size(token_array) + 1
    rule_id = :erlang.phash2(rule)

    columns = :array.new(size, default: nil)
    columns = :array.set(0, Column.new(0), columns)

    columns =
      Enum.reduce(1..(size - 1), columns, fn i, cols ->
        token = elem(token_array, i - 1)
        :array.set(i, Column.new(i, token), cols)
      end)

    columns =
      Enum.reduce(0..(size - 1), columns, fn i, cols ->
        col = :array.get(i, cols)

        col =
          Enum.reduce(rule.productions, col, fn prod, col ->
            prod_id = {rule_id, :erlang.phash2(prod)}
            state = State.new(rule, rule_id, prod, prod_id, start: i, stop: i)
            Column.add(col, state)
          end)

        {col, cols} = process_column(col, cols, i, size)
        :array.set(i, col, cols)
      end)

    columns
  end

  defp process_column(col, cols, col_index, size) do
    process_states(col, cols, 0, col_index, size)
  end

  defp process_states(col, cols, state_index, _col_index, _size) when state_index >= col.count do
    {col, cols}
  end

  defp process_states(col, cols, state_index, col_index, size) do
    state = Column.get_state(col, state_index)
    {col, cols} = process_single_state(col, cols, state, col_index, size)
    process_states(col, cols, state_index + 1, col_index, size)
  end

  defp process_single_state(col, cols, state, col_index, size) do
    if State.completed?(state) do
      complete(col, cols, state)
    else
      next_term = State.next_term(state)

      if Rule.non_terminal?(next_term) do
        col = predict(col, next_term)
        {col, cols}
      else
        cols = scan(cols, state, next_term, col_index, size)
        {col, cols}
      end
    end
  end

  defp predict(col, rule) do
    {resolved_rule, rule_id} =
      case rule do
        %Rule{name: {:forward, _}} = fwd ->
          resolved = Rule.resolve_forward(fwd)
          {resolved, :erlang.phash2(resolved)}

        _ ->
          {rule, :erlang.phash2(rule)}
      end

    case col.predicted do
      %{^rule_id => true} ->
        col

      _ ->
        col = %{col | predicted: Map.put(col.predicted, rule_id, true)}

        Enum.reduce(resolved_rule.productions, col, fn prod, col ->
          prod_id = {rule_id, :erlang.phash2(prod)}
          state = State.new(rule, rule_id, prod, prod_id, start: col.index, stop: col.index)
          Column.add(col, state)
        end)
    end
  end

  defp scan(cols, state, predicate, col_index, size) when is_function(predicate) do
    next_index = col_index + 1

    if next_index < size do
      next_col = :array.get(next_index, cols)

      if next_col.token && predicate.(next_col.token) do
        advanced = State.advance(state, next_index, {:leaf, next_col.token})
        next_col = Column.add(next_col, advanced)
        :array.set(next_index, next_col, cols)
      else
        cols
      end
    else
      cols
    end
  end

  defp complete(col, cols, completed) do
    start_col =
      if completed.start == col.index do
        col
      else
        :array.get(completed.start, cols)
      end

    parents = Column.waiting_for(start_col, :erlang.phash2(completed.rule))

    col =
      Enum.reduce(parents, col, fn parent, col ->
        advanced = State.advance(parent, completed.stop, {:node, completed})
        Column.add(col, advanced)
      end)

    {col, cols}
  end

  defp completed_states(columns, rule) do
    rule_id = :erlang.phash2(rule)
    size = :array.size(columns)

    Enum.flat_map(0..(size - 1), fn i ->
      col = :array.get(i, columns)

      col
      |> Column.all_states()
      |> Enum.filter(fn state ->
        State.completed?(state) and state.rule_id == rule_id
      end)
    end)
  end

  defp resolve_overlaps(matches) do
    resolve_overlaps(matches, [], 0)
  end

  defp resolve_overlaps([], acc, _), do: Enum.reverse(acc)

  defp resolve_overlaps([match | rest], acc, max_stop) do
    if match.start < max_stop do
      resolve_overlaps(rest, acc, max_stop)
    else
      new_max = max(max_stop, match.stop)
      resolve_overlaps(rest, [match | acc], new_max)
    end
  end
end
