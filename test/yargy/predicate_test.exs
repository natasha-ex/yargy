defmodule Yargy.PredicateTest do
  use ExUnit.Case, async: true

  alias Yargy.{Predicate, Token}

  defp token(value, type \\ :word) do
    Token.new(value, type, 0, String.length(value))
  end

  test "eq matches exact value" do
    p = Predicate.eq("ст")
    assert p.(token("ст"))
    refute p.(token("СТ"))
  end

  test "caseless matches case-insensitively" do
    p = Predicate.caseless("ст")
    assert p.(token("ст"))
    assert p.(token("Ст"))
    assert p.(token("СТ"))
  end

  test "in_ matches set membership" do
    p = Predicate.in_(~w(ГК ГПК АПК))
    assert p.(token("ГК"))
    assert p.(token("АПК"))
    refute p.(token("ТК"))
  end

  test "type matches token type" do
    p = Predicate.type(:int)
    assert p.(token("42", :int))
    refute p.(token("abc", :word))
  end

  test "gram matches morphological grammeme" do
    p = Predicate.gram("NOUN")

    t = %Token{
      value: "договор",
      type: :word,
      start: 0,
      stop: 7,
      forms: [%{normalized: "договор", grams: MapSet.new(["NOUN", "masc", "inan"])}]
    }

    assert p.(t)
  end

  test "dictionary matches normalized forms" do
    p = Predicate.dictionary(~w(договор контракт соглашение))

    t = %Token{
      value: "договора",
      type: :word,
      start: 0,
      stop: 8,
      forms: [%{normalized: "договор", grams: MapSet.new(["NOUN"])}]
    }

    assert p.(t)
  end

  test "and_ combines predicates" do
    p = Predicate.and_(Predicate.type(:word), Predicate.capitalized?())
    assert p.(token("Москва"))
    refute p.(token("москва"))
  end

  test "not_ negates" do
    p = Predicate.not_(Predicate.type(:punct))
    assert p.(token("слово"))
    refute p.(token(".", :punct))
  end
end
