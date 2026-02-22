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

  describe "partial_matches/2" do
    test "detects incomplete two-token sequence" do
      rule = Rule.rule([Predicate.eq("ст"), Predicate.eq("."), Predicate.type(:int)])
      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("ст.")

      partials = Parser.partial_matches(parser, tokens)

      assert [%{dot: 2, production_length: 3, matched_text: "ст ."}] = partials
    end

    test "detects single-token progress" do
      rule = Rule.rule([Predicate.eq("ст"), Predicate.eq("."), Predicate.type(:int)])
      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("ст")

      partials = Parser.partial_matches(parser, tokens)

      assert [%{dot: 1, production_length: 3}] = partials
    end

    test "returns empty for complete match" do
      rule = Rule.rule([Predicate.eq("ст"), Predicate.eq(".")])
      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("ст.")

      assert [] = Parser.partial_matches(parser, tokens)
    end

    test "returns empty when nothing matches" do
      rule = Rule.rule([Predicate.eq("ст"), Predicate.eq(".")])
      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("привет мир")

      assert [] = Parser.partial_matches(parser, tokens)
    end

    test "finds partial in surrounding text" do
      rule =
        Rule.rule([
          Predicate.in_(~w(ООО ПАО АО)),
          Predicate.or_([Predicate.eq("«"), Predicate.eq("\"")]),
          Predicate.type(:word),
          Predicate.or_([Predicate.eq("»"), Predicate.eq("\"")])
        ])

      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("Директору ООО «Ромашка")

      partials = Parser.partial_matches(parser, tokens)

      assert [%{dot: 3, production_length: 4, matched_text: "ООО « Ромашка"}] = partials
    end

    test "progress is a fraction of matched/total" do
      rule = Rule.rule([Predicate.eq("a"), Predicate.eq("b"), Predicate.eq("c"), Predicate.eq("d")])
      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("a b")

      partials = Parser.partial_matches(parser, tokens)

      assert [%{progress: 0.5}] = partials
    end

    test "deduplicates by rule name" do
      inner = Rule.rule([Predicate.type(:word)]) |> Rule.named("Word")
      rule = Rule.rule([[inner, Predicate.eq(".")]]) |> Rule.named("Main")
      parser = Parser.new(rule)
      tokens = Tokenizer.tokenize("привет")

      partials = Parser.partial_matches(parser, tokens)

      rule_names = Enum.map(partials, & &1.rule_name)
      assert rule_names == Enum.uniq(rule_names)
    end
  end
end
