defmodule Yargy.MorphPipeline do
  @moduledoc """
  Multi-word phrase matcher that handles inflected forms.

  Given a list of phrases like `["закрытое акционерное общество", "завод"]`,
  generates grammar rules that match any inflected variant of each phrase.

  ## Usage

      rule = MorphPipeline.rule(["закрытое общество", "завод"])
      parser = Parser.new(rule)
      # Matches "закрытому обществу", "заводе", etc.
  """

  alias Yargy.{Predicate, Rule}

  @doc """
  Builds a rule that matches any of the given phrases in any inflected form.

  Each phrase is split into words and matched by normalized form.
  The resulting rule carries a `pipeline_key` metadata for interpretation.
  """
  def rule(phrases) when is_list(phrases) do
    productions =
      Enum.flat_map(phrases, fn phrase ->
        words = String.split(phrase)
        lemmas = Enum.map(words, &normalize_word/1)

        terms =
          Enum.map(lemmas, fn lemma_set ->
            Predicate.normalized_in(lemma_set)
          end)

        [Rule.Production.new(terms)]
      end)

    %Rule{productions: productions, name: "MorphPipeline"}
  end

  defp normalize_word(word) do
    case MorphRu.normal_forms(word) do
      [] -> [String.downcase(word)]
      forms -> forms
    end
  end
end
