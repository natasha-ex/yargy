defmodule Yargy.TokenizerTest do
  use ExUnit.Case, async: true

  alias Yargy.Tokenizer

  test "tokenizes Russian text with positions" do
    tokens = Tokenizer.tokenize("ст. 309 ГК РФ")

    values = Enum.map(tokens, & &1.value)
    assert values == ["ст", ".", "309", "ГК", "РФ"]

    types = Enum.map(tokens, & &1.type)
    assert types == [:word, :punct, :int, :word, :word]
  end

  test "preserves character positions" do
    tokens = Tokenizer.tokenize("abc 123")
    [t1, t2] = tokens

    assert t1.start == 0
    assert t1.stop == 3
    assert t2.start == 4
    assert t2.stop == 7
  end

  test "handles Cyrillic with hyphens" do
    tokens = Tokenizer.tokenize("вице-мэр города")
    values = Enum.map(tokens, & &1.value)
    assert values == ["вице", "-", "мэр", "города"]
  end

  test "handles punctuation" do
    tokens = Tokenizer.tokenize("(ДНР)")
    values = Enum.map(tokens, & &1.value)
    assert values == ["(", "ДНР", ")"]
  end

  test "handles amounts with decimals" do
    tokens = Tokenizer.tokenize("2500000 рублей")
    [amount, _] = tokens
    assert amount.type == :int
    assert amount.value == "2500000"
  end
end
