defmodule Yargy.BugChoiceTest do
  use ExUnit.Case, async: true
  use Yargy.Grammar

  defrule :noun, gram("NOUN")
  defrule :obligation_verb, lemma(~w[обязать должный обязанный обязан])
  defrule :bear_verb, lemma("нести")

  defgrammar :obligation_pattern,
             choice([
               rule(:noun) ~> rule(:obligation_verb),
               rule(:noun) ~> rule(:bear_verb),
               rule(:obligation_verb),
               rule(:bear_verb)
             ])

  test "choice with sequence and standalone alternatives" do
    tokens = "Должник обязан" |> Yargy.Tokenizer.tokenize() |> Yargy.MorphTagger.tag()
    parser = obligation_pattern_parser()
    matches = Yargy.Parser.findall(parser, tokens)

    assert length(matches) == 1
    assert Enum.map(hd(matches).tokens, & &1.value) == ["Должник", "обязан"]
  end

  test "standalone alternative still matches when no noun precedes" do
    tokens = "обязан возместить" |> Yargy.Tokenizer.tokenize() |> Yargy.MorphTagger.tag()
    parser = obligation_pattern_parser()
    matches = Yargy.Parser.findall(parser, tokens)

    assert length(matches) == 1
    assert Enum.map(hd(matches).tokens, & &1.value) == ["обязан"]
  end
end
