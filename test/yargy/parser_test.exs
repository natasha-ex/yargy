defmodule Yargy.ParserTest do
  use ExUnit.Case, async: true

  alias Yargy.{Parser, Predicate, Rule, Tokenizer}

  test "parses a simple two-token sequence" do
    rule = Rule.rule([Predicate.eq("ст"), Predicate.eq(".")])
    parser = Parser.new(rule)

    tokens = Tokenizer.tokenize("ст.")
    matches = Parser.findall(parser, tokens)

    assert length(matches) == 1
    assert hd(matches).start == 0
    assert hd(matches).stop == 2
  end

  test "finds multiple non-overlapping matches" do
    number = Predicate.type(:int)
    rule = Rule.rule([number])
    parser = Parser.new(rule)

    tokens = Tokenizer.tokenize("в 2025 году было 3 претензии")
    matches = Parser.findall(parser, tokens)

    values = Enum.map(matches, &Parser.Match.text/1)
    assert "2025" in values
    assert "3" in values
  end

  test "parses rule with non-terminal" do
    prefix = Rule.rule([Predicate.in_caseless(~w(ст статья))])
    dot = Rule.optional(Rule.rule([Predicate.eq(".")]))
    number = Rule.rule([Predicate.type(:int)])

    article = Rule.rule([[prefix, dot, number]])
    parser = Parser.new(article)

    tokens = Tokenizer.tokenize("ст. 309")
    matches = Parser.findall(parser, tokens)

    assert length(matches) == 1
    assert Parser.Match.text(hd(matches)) =~ "309"
  end

  test "returns empty for no matches" do
    rule = Rule.rule([Predicate.eq("несуществующее")])
    parser = Parser.new(rule)

    tokens = Tokenizer.tokenize("обычный текст без совпадений")
    matches = Parser.findall(parser, tokens)

    assert matches == []
  end
end
