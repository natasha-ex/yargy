defmodule Yargy.MorphPipelineTest do
  use ExUnit.Case

  alias Yargy.{MorphPipeline, Parser, Pipeline}

  defp findall(phrases, text) do
    rule = MorphPipeline.rule(phrases)
    tokens = Pipeline.morph_tokenize(text)
    parser = Parser.new(rule)

    Parser.findall(parser, tokens)
    |> Enum.map(&Parser.Match.text/1)
  end

  describe "morph_pipeline" do
    test "matches exact phrase" do
      results = findall(["закрытое общество"], "это закрытое общество")
      assert results == ["закрытое общество"]
    end

    test "matches inflected phrase" do
      results = findall(["закрытое общество"], "в закрытом обществе работать")
      assert results == ["закрытом обществе"]
    end

    test "matches single word in different form" do
      results = findall(["завод"], "на заводе построили цех")
      assert results == ["заводе"]
    end

    test "matches multiple phrases" do
      results =
        findall(
          ["акционерное общество", "договор поставки"],
          "между акционерным обществом заключен договор поставки"
        )

      assert length(results) == 2
    end

    test "no match for unrelated text" do
      results = findall(["закрытое общество"], "открытый рынок")
      assert results == []
    end

    test "matches phrase from Python test_pipeline_key" do
      results = findall(["закрытое общество", "завод"], "закрытом обществе")
      assert results == ["закрытом обществе"]
    end

    test "matches single word from Python test_pipeline_key" do
      results = findall(["закрытое общество", "завод"], "заводе")
      assert results == ["заводе"]
    end
  end
end
