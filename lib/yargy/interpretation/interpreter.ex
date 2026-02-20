defmodule Yargy.Interpretation.Interpreter do
  @moduledoc """
  Walks a parse tree and applies interpretation specs to extract structured facts.

  The parse tree is represented as `{:node, rule, children}` or `{:leaf, token}`.
  Each node's rule may carry an interpretation spec. The interpreter processes
  bottom-up: leaf tokens → inner nodes → root fact.
  """

  alias Yargy.Interpretation.{Fact, Spec}
  alias Yargy.Token

  @doc """
  Interprets a parse tree, returning the extracted value.

  The tree is `{:node, rule, children}` or `{:leaf, token}`.
  """
  def interpret(tree) do
    result = do_interpret(tree)
    normalize_result(result)
  end

  defp do_interpret({:leaf, token}), do: {:token, token}

  defp do_interpret({:node, rule, children}) do
    child_results = Enum.map(children, &do_interpret/1)

    case rule[:interpretation] do
      nil -> {:items, child_results}
      spec -> apply_spec(spec, child_results, rule)
    end
  end

  defp apply_spec(%Spec{type: :fact, schema: schema}, children, _rule) do
    fact = Fact.new(schema)

    fact =
      children
      |> List.flatten()
      |> Enum.reduce(fact, fn
        {:attr, s, key, value}, acc when s.name == schema.name ->
          Fact.set(acc, schema, key, value)

        {:fact_result, %Fact{__schema__: name} = child_fact}, acc when name == schema.name ->
          Fact.merge(acc, child_fact)

        _, acc ->
          acc
      end)

    spans = collect_spans(children)
    {:fact_result, %{fact | __raw__: spans}}
  end

  defp apply_spec(%Spec{type: :attribute, schema: schema, attr: attr}, children, _rule) do
    value = unwrap_single_result(children) || join_token_values(children)
    {:attr, schema, attr, value}
  end

  defp apply_spec(%Spec{type: :normalized}, children, rule) do
    tokens = collect_tokens(children)
    {:value, join_normalized(tokens, rule)}
  end

  defp apply_spec(%Spec{type: :inflected, grams: grams}, children, _rule) do
    tokens = collect_tokens(children)
    {:value, join_inflected(tokens, grams)}
  end

  defp apply_spec(%Spec{type: :const, value: value}, _children, _rule) do
    {:value, value}
  end

  defp apply_spec(%Spec{type: :custom, fun: fun}, children, _rule) do
    value = join_token_values(children)
    {:value, fun.(value)}
  end

  defp apply_spec(%Spec{type: :custom_chain, funs: funs}, children, _rule) do
    value = join_token_values(children)
    {:value, Enum.reduce(funs, value, fn f, v -> f.(v) end)}
  end

  defp apply_spec(%Spec{type: :attr_normalized, schema: schema, attr: attr}, children, rule) do
    tokens = collect_tokens(children)
    {:attr, schema, attr, join_normalized(tokens, rule)}
  end

  defp apply_spec(
         %Spec{type: :attr_inflected, schema: schema, attr: attr, grams: grams},
         children,
         _rule
       ) do
    tokens = collect_tokens(children)
    {:attr, schema, attr, join_inflected(tokens, grams)}
  end

  defp apply_spec(
         %Spec{type: :attr_const, schema: schema, attr: attr, value: value},
         _children,
         _rule
       ) do
    {:attr, schema, attr, value}
  end

  defp apply_spec(
         %Spec{type: :attr_custom, schema: schema, attr: attr, fun: fun},
         children,
         _rule
       ) do
    value = join_token_values(children)
    {:attr, schema, attr, fun.(value)}
  end

  defp apply_spec(
         %Spec{type: :attr_normalized_custom, schema: schema, attr: attr, fun: fun},
         children,
         rule
       ) do
    tokens = collect_tokens(children)
    {:attr, schema, attr, fun.(join_normalized(tokens, rule))}
  end

  defp apply_spec(
         %Spec{type: :attr_inflected_custom, schema: schema, attr: attr, grams: grams, fun: fun},
         children,
         _rule
       ) do
    tokens = collect_tokens(children)
    {:attr, schema, attr, fun.(join_inflected(tokens, grams))}
  end

  defp apply_spec(%Spec{type: :normalized_custom, fun: fun}, children, rule) do
    tokens = collect_tokens(children)
    {:value, fun.(join_normalized(tokens, rule))}
  end

  defp apply_spec(%Spec{type: :inflected_custom, grams: grams, fun: fun}, children, _rule) do
    tokens = collect_tokens(children)
    {:value, fun.(join_inflected(tokens, grams))}
  end

  defp unwrap_single_result(children) do
    flat = List.flatten(children)

    case flat do
      [{:fact_result, fact}] -> fact
      [{:value, value}] -> value
      [{:attr, _, _, value}] -> value
      _ -> nil
    end
  end

  defp collect_tokens(children) do
    children
    |> List.flatten()
    |> Enum.flat_map(fn
      {:token, token} -> [token]
      {:items, items} -> collect_tokens(items)
      _ -> []
    end)
  end

  defp collect_spans(children) do
    children
    |> List.flatten()
    |> Enum.flat_map(fn
      {:token, %Token{start: s, stop: e}} -> [{s, e}]
      {:attr, _, _, _} -> []
      {:fact_result, fact} -> Fact.spans(fact)
      {:items, items} -> collect_spans(items)
      {:value, _} -> []
    end)
  end

  defp join_token_values(children) do
    children
    |> collect_tokens()
    |> Enum.map_join(" ", & &1.value)
  end

  defp join_normalized(tokens, rule) do
    pipeline_key = rule[:pipeline_key]

    if pipeline_key do
      pipeline_key
    else
      Enum.map_join(tokens, " ", &Token.normalized/1)
    end
  end

  defp join_inflected(tokens, grams) do
    Enum.map_join(tokens, " ", &inflect_token(&1, grams))
  end

  defp inflect_token(%Token{} = token, grams) do
    case MorphRu.parse(token.value) do
      [parse | _] ->
        case MorphRu.inflect(parse, grams) do
          nil -> token.value
          inflected -> inflected.word
        end

      [] ->
        token.value
    end
  end

  defp normalize_result({:fact_result, fact}), do: fact
  defp normalize_result({:value, value}), do: value
  defp normalize_result({:attr, _schema, _key, value}), do: value
  defp normalize_result({:token, token}), do: token.value
  defp normalize_result({:items, items}), do: normalize_result(List.last(items))
end
