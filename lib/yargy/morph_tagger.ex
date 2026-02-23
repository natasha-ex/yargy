defmodule Yargy.MorphTagger do
  @moduledoc """
  Enriches tokens with morphological analysis from MorphRu.

  Populates `token.forms` with `%{normalized: ..., grams: MapSet}` entries
  so that `gram/1`, `normalized/1`, and `dictionary/1` predicates work.
  """

  alias Yargy.Token

  @doc "Adds morphological forms to each word token."
  def tag(tokens) when is_list(tokens) do
    {tagged, _cache} =
      Enum.map_reduce(tokens, %{}, fn token, cache ->
        tag_token(token, cache)
      end)

    tagged
  end

  defp tag_token(%Token{type: :word, value: value} = token, cache) do
    {forms, cache} =
      case Map.fetch(cache, value) do
        {:ok, cached_forms} ->
          {cached_forms, cache}

        :error ->
          forms =
            value
            |> MorphRu.parse()
            |> Enum.map(fn parse ->
              %{normalized: parse.normal_form, grams: parse.tag.grammemes}
            end)

          {forms, Map.put(cache, value, forms)}
      end

    {Token.with_forms(token, forms), cache}
  end

  defp tag_token(token, cache), do: {token, cache}
end
