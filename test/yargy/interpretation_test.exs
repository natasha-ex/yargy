defmodule Yargy.InterpretationTest do
  use ExUnit.Case

  alias Yargy.Interpretation.{Fact, Spec}
  alias Yargy.{Parser, Pipeline, Predicate, Rule}
  alias Yargy.Parser.Match

  defp match(rule, text) do
    tokens = Pipeline.morph_tokenize(text)
    parser = Parser.new(rule)
    Parser.find(parser, tokens)
  end

  describe "basic fact extraction" do
    test "predicate attribute" do
      schema = Fact.define("F", [:a])

      rule =
        Rule.rule([Predicate.eq("a")])
        |> Rule.interpretation(Spec.attribute(schema, :a))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "a")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == "a"
    end

    test "merge facts" do
      schema = Fact.define("F", [:a, :b])

      a_rule =
        Rule.rule([Predicate.eq("a")])
        |> Rule.interpretation(Spec.attribute(schema, :a))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      b_rule =
        Rule.rule([Predicate.eq("b")])
        |> Rule.interpretation(Spec.attribute(schema, :b))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      rule =
        Rule.rule([[a_rule, b_rule]])
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "a b")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == "a"
      assert Fact.get(fact, :b) == "b"
    end

    test "rule attribute (multi-token)" do
      schema = Fact.define("F", [:a])

      inner =
        Rule.rule([[Predicate.caseless("a"), Predicate.caseless("A")]])
        |> Rule.interpretation(Spec.attribute(schema, :a))

      rule =
        Rule.rule([[inner]])
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "a   A")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == "a A"
    end
  end

  describe "normalizers" do
    test "normalized()" do
      rule =
        Rule.rule([Predicate.caseless("московским")])
        |> Rule.interpretation(Spec.normalized())

      m = match(rule, "московским")
      assert Match.fact(m) == "московский"
    end

    test "inflected()" do
      rule =
        Rule.rule([Predicate.caseless("московским")])
        |> Rule.interpretation(Spec.inflected(["nomn", "femn"]))

      m = match(rule, "московским")
      assert Match.fact(m) == "московская"
    end

    test "const()" do
      rule =
        Rule.rule([Predicate.eq("a")])
        |> Rule.interpretation(Spec.const(1))

      m = match(rule, "a")
      assert Match.fact(m) == 1
    end

    test "custom()" do
      rule =
        Rule.rule([Predicate.caseless("1")])
        |> Rule.interpretation(Spec.custom(&String.to_integer/1))

      m = match(rule, "1")
      assert Match.fact(m) == 1
    end

    test "custom chain" do
      mapping = %{"a" => 1}

      rule =
        Rule.rule([Predicate.caseless("A")])
        |> Rule.interpretation(Spec.custom_chain([&String.downcase/1, &Map.get(mapping, &1)]))

      m = match(rule, "A")
      assert Match.fact(m) == 1
    end

    test "normalized + custom" do
      months = %{"январь" => 1}

      rule =
        Rule.rule([Predicate.caseless("январе")])
        |> Rule.interpretation(Spec.normalized_custom(&Map.get(months, &1)))

      m = match(rule, "январе")
      assert Match.fact(m) == 1
    end

    test "inflected + custom" do
      months = %{"январь" => 1}

      rule =
        Rule.rule([Predicate.caseless("январе")])
        |> Rule.interpretation(Spec.inflected_custom(["nomn", "sing"], &Map.get(months, &1)))

      m = match(rule, "январе")
      assert Match.fact(m) == 1
    end
  end

  describe "attribute normalizers" do
    test "attribute + normalized" do
      schema = Fact.define("F", [:a])

      rule =
        Rule.rule([Predicate.caseless("январе")])
        |> Rule.interpretation(Spec.attr_normalized(schema, :a))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "январе")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == "январь"
    end

    test "attribute + inflected" do
      schema = Fact.define("F", [:a])

      rule =
        Rule.rule([Predicate.caseless("январе")])
        |> Rule.interpretation(Spec.attr_inflected(schema, :a, ["nomn", "plur"]))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "январе")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == "январи"
    end

    test "attribute + const" do
      schema = Fact.define("F", [:a])

      rule =
        Rule.rule([Predicate.caseless("январь")])
        |> Rule.interpretation(Spec.attr_const(schema, :a, 1))

      m = match(rule, "январь")
      assert Match.fact(m) == 1
    end

    test "attribute + custom" do
      schema = Fact.define("F", [:a])

      rule =
        Rule.rule([Predicate.caseless("1")])
        |> Rule.interpretation(Spec.attr_custom(schema, :a, &String.to_integer/1))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "1")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == 1
    end

    test "attribute + normalized + custom" do
      schema = Fact.define("F", [:a])
      months = %{"январь" => 1}

      rule =
        Rule.rule([Predicate.caseless("январе")])
        |> Rule.interpretation(Spec.attr_normalized_custom(schema, :a, &Map.get(months, &1)))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "январе")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == 1
    end

    test "attribute + inflected + custom" do
      schema = Fact.define("F", [:a])
      months = %{"январь" => 1}

      rule =
        Rule.rule([Predicate.caseless("январе")])
        |> Rule.interpretation(
          Spec.attr_inflected_custom(schema, :a, ["nomn", "sing"], &Map.get(months, &1))
        )
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "январе")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == 1
    end
  end

  describe "insted attributes (attribute wrapping)" do
    test "attribute overrides with rule-level attribute" do
      schema = Fact.define("F", [:a, :b])

      rule =
        Rule.rule([Predicate.eq("a")])
        |> Rule.interpretation(Spec.attribute(schema, :a))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.attribute(schema, :b))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "a")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == nil
      assert Fact.get(fact, :b) == "a"
    end
  end

  describe "rule custom then attribute" do
    test "custom at rule level, then attribute wrapping" do
      schema = Fact.define("F", [:a])

      inner =
        Rule.rule([Predicate.caseless("1")])
        |> Rule.interpretation(Spec.custom(&String.to_integer/1))

      rule =
        Rule.rule([[inner]])
        |> Rule.interpretation(Spec.attribute(schema, :a))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "1")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == 1
    end
  end

  describe "nested facts" do
    test "fact inside fact" do
      f_schema = Fact.define("F", [:a])
      g_schema = Fact.define("G", [:b])

      rule =
        Rule.rule([Predicate.eq("a")])
        |> Rule.interpretation(Spec.attribute(f_schema, :a))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(f_schema))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.attribute(g_schema, :b))
        |> then(&Rule.rule([&1]))
        |> Rule.interpretation(Spec.fact(g_schema))

      m = match(rule, "a")
      fact = Match.fact(m)
      assert fact.__schema__ == :G
      inner = Fact.get(fact, :b)
      assert inner.__schema__ == :F
      assert Fact.get(inner, :a) == "a"
    end
  end

  describe "repeatable attributes" do
    test "repeatable collects multiple values" do
      schema = Fact.define("F", [{:repeatable, :a}])

      rule =
        Rule.rule([
          [
            Rule.rule([Predicate.eq("a")]) |> Rule.interpretation(Spec.attribute(schema, :a)),
            Rule.rule([Predicate.eq("b")]) |> Rule.interpretation(Spec.attribute(schema, :a))
          ]
        ])
        |> Rule.interpretation(Spec.fact(schema))

      m = match(rule, "a b")
      fact = Match.fact(m)
      assert Fact.get(fact, :a) == ["a", "b"]
    end
  end

  describe "as_json" do
    test "simple fact" do
      schema = Fact.define("F", [:a, :b])
      fact = Fact.new(schema, a: "hello", b: 42)
      assert Fact.as_json(fact) == %{a: "hello", b: 42}
    end

    test "nested fact" do
      inner_schema = Fact.define("Inner", [:x])
      outer_schema = Fact.define("Outer", [:y])
      inner = Fact.new(inner_schema, x: "value")
      outer = Fact.new(outer_schema, y: inner)
      assert Fact.as_json(outer) == %{y: %{x: "value"}}
    end
  end

  describe "custom multi-token" do
    test "custom on multi-token rule (float)" do
      rule =
        Rule.rule([[Predicate.caseless("3"), Predicate.eq("."), Predicate.caseless("14")]])
        |> Rule.interpretation(
          Spec.custom(fn s ->
            s |> String.replace(" ", "") |> String.to_float()
          end)
        )

      m = match(rule, "3.14")
      assert Match.fact(m) == 3.14
    end
  end
end
