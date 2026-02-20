defmodule Yargy.Pipeline do
  @moduledoc """
  Token processing pipelines for Yargy grammars.

  - `tokenize/1` — plain tokenization (no morphology)
  - `morph_tokenize/1` — tokenize + morphological tagging via MorphRu
  """

  alias Yargy.{MorphTagger, Tokenizer}

  @doc "Tokenizes text without morphological analysis."
  def tokenize(text), do: Tokenizer.tokenize(text)

  @doc "Tokenizes text and enriches word tokens with morphological forms."
  def morph_tokenize(text) do
    text |> Tokenizer.tokenize() |> MorphTagger.tag()
  end
end
