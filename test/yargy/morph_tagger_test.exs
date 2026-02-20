defmodule Yargy.MorphTaggerTest do
  use ExUnit.Case

  alias Yargy.{MorphTagger, Predicate, Tokenizer}

  defp tagged(text) do
    text |> Tokenizer.tokenize() |> MorphTagger.tag()
  end

  describe "tag/1" do
    test "populates forms for word tokens" do
      [token | _] = tagged("договор")
      assert token.forms != []
      assert Enum.any?(token.forms, &MapSet.member?(&1.grams, "NOUN"))
    end

    test "leaves punct tokens without forms" do
      tokens = tagged("привет!")
      punct = Enum.find(tokens, &(&1.type == :punct))
      assert punct.forms == []
    end
  end

  describe "gram predicate with morph" do
    test "gram NOUN matches nouns" do
      [token | _] = tagged("договор")
      assert Predicate.gram("NOUN").(token)
    end

    test "gram VERB matches verbs" do
      tokens = tagged("подписали документ")
      verb = hd(tokens)
      assert Predicate.gram("VERB").(verb)
    end

    test "gram ADJF matches adjectives" do
      [token | _] = tagged("красивый")
      assert Predicate.gram("ADJF").(token)
    end

    test "gram gent matches genitive case" do
      [token | _] = tagged("договора")
      assert Predicate.gram("gent").(token)
    end
  end

  describe "normalized predicate with morph" do
    test "matches normal form" do
      [token | _] = tagged("договоров")
      assert Predicate.normalized("договор").(token)
    end

    test "matches through inflection" do
      [token | _] = tagged("подписали")
      assert Predicate.normalized("подписать").(token)
    end

    test "rejects wrong lemma" do
      [token | _] = tagged("договоров")
      refute Predicate.normalized("контракт").(token)
    end
  end

  describe "dictionary predicate with morph" do
    test "matches word in dictionary" do
      [token | _] = tagged("ответчика")
      assert Predicate.dictionary(~w(ответчик истец суд)).(token)
    end

    test "rejects word not in dictionary" do
      [token | _] = tagged("ответчика")
      refute Predicate.dictionary(~w(истец суд)).(token)
    end
  end
end
