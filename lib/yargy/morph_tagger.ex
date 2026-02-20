defmodule Yargy.MorphTagger do
  @moduledoc """
  Enriches tokens with morphological analysis from MorphRu.

  Populates `token.forms` with `%{normalized: ..., grams: MapSet}` entries
  so that `gram/1`, `normalized/1`, and `dictionary/1` predicates work.
  """

  alias Yargy.Token

  @doc "Adds morphological forms to each word token."
  def tag(tokens) when is_list(tokens) do
    Enum.map(tokens, &tag_token/1)
  end

  defp tag_token(%Token{type: :word, value: value} = token) do
    forms =
      value
      |> MorphRu.parse()
      |> Enum.map(fn parse ->
        %{normalized: parse.normal_form, grams: parse.tag.grammemes}
      end)

    Token.with_forms(token, forms)
  end

  defp tag_token(token), do: token
end
