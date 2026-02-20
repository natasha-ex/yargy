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

    @enforce_keys [:rule, :production, :dot, :start, :stop]
    defstruct [:rule, :production, :dot, :start, :stop, children: []]

    def new(rule, production, opts \\ []) do
      %__MODULE__{
        rule: rule,
        production: production,
        dot: opts[:dot] || 0,
        start: opts[:start] || 0,
        stop: opts[:stop] || 0,
        children: opts[:children] || []
      }
    end

    def completed?(%__MODULE__{dot: dot, production: prod}) do
      dot >= length(prod.terms)
    end

    def next_term(%__MODULE__{dot: dot, production: prod}) do
      Enum.at(prod.terms, dot)
    end

    def advance(%__MODULE__{} = state, stop, child) do
      %{state | dot: state.dot + 1, stop: stop, children: [child | state.children]}
    end

    def key(%__MODULE__{} = state) do
      {id(state.rule), id(state.production), state.dot, state.start, state.stop}
    end

    defp id(term), do: :erlang.phash2(term)
  end

  defmodule Column do
    @moduledoc false

    defstruct [:index, :token, states: nil, count: 0, seen: MapSet.new(), waiting: %{}]

    def new(index, token \\ nil) do
      %__MODULE__{index: index, token: token, states: :array.new(default: nil)}
    end

    def add(%__MODULE__{} = col, %State{} = state) do
      key = State.key(state)

      if MapSet.member?(col.seen, key) do
        col
      else
        col = %{
          col
          | states: :array.set(col.count, state, col.states),
            count: col.count + 1,
            seen: MapSet.put(col.seen, key)
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

    def waiting_for(%__MODULE__{waiting: waiting}, rule) do
      rule_id = :erlang.phash2(rule)
      Map.get(waiting, rule_id, [])
    end
  end

  defmodule Match do
    @moduledoc "A successful parse match with tokens and span."

    alias Yargy.Interpretation.Interpreter
    alias Yargy.Relations

    defstruct [:rule, :tokens, :start, :stop, :children]

    def new(state, all_tokens) do
      tokens = Enum.slice(all_tokens, state.start, state.stop - state.start)

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
    chart = parse(rule, tokens)

    matches =
      chart
      |> completed_states(rule)
      |> Enum.map(&Match.new(&1, tokens))
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

  defp parse(rule, tokens) do
    token_array = List.to_tuple(tokens)
    size = tuple_size(token_array) + 1

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
            state = State.new(rule, prod, start: i, stop: i)
            Column.add(col, state)
          end)

        {col, cols} = process_column(col, cols, i, size)
        :array.set(i, col, cols)
      end)

    for i <- 0..(size - 1), do: :array.get(i, columns)
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
    productions =
      case rule do
        %Rule{name: {:forward, _}} = fwd ->
          Rule.resolve_forward(fwd).productions

        _ ->
          rule.productions
      end

    Enum.reduce(productions, col, fn prod, col ->
      state = State.new(rule, prod, start: col.index, stop: col.index)
      Column.add(col, state)
    end)
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

    parents = Column.waiting_for(start_col, completed.rule)

    col =
      Enum.reduce(parents, col, fn parent, col ->
        advanced = State.advance(parent, completed.stop, {:node, completed})
        Column.add(col, advanced)
      end)

    {col, cols}
  end

  defp completed_states(columns, rule) do
    rule_hash = :erlang.phash2(rule)

    Enum.flat_map(columns, fn col ->
      col
      |> Column.all_states()
      |> Enum.filter(fn state ->
        State.completed?(state) and :erlang.phash2(state.rule) == rule_hash
      end)
    end)
  end

  defp resolve_overlaps(matches) do
    Enum.reduce(matches, [], fn match, acc ->
      if overlaps_any?(acc, match), do: acc, else: acc ++ [match]
    end)
  end

  defp overlaps_any?(accepted, match) do
    Enum.any?(accepted, fn prev -> overlaps?(prev, match) end)
  end

  defp overlaps?(m1, m2) do
    m1.start < m2.stop and m2.start < m1.stop
  end
end
