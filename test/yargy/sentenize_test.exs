defmodule Yargy.SentenizeTest do
  use ExUnit.Case

  alias Yargy.Sentenize

  describe "sentences/1" do
    test "basic sentence split" do
      text = "Первое предложение. Второе предложение."
      assert Sentenize.sentences(text) == ["Первое предложение.", "Второе предложение."]
    end

    test "abbreviation ст. does not split" do
      text = "В соответствии со ст. 309 ГК РФ обязательства должны исполняться."
      result = Sentenize.sentences(text)
      assert length(result) == 1
    end

    test "abbreviation п. does not split" do
      text = "Согласно п. 1 ст. 10 ГК РФ действия запрещены."
      result = Sentenize.sentences(text)
      assert length(result) == 1
    end

    test "initials do not split" do
      text = "Директор А.В. Иванов подписал документ. Это важно."
      result = Sentenize.sentences(text)
      assert length(result) == 2
      assert hd(result) =~ "Иванов"
    end

    test "т.е. does not split" do
      text = "Истец, т.е. ООО «Ромашка», обратился в суд. Ответчик не явился."
      result = Sentenize.sentences(text)
      assert length(result) == 2
    end

    test "question mark splits" do
      text = "Почему? Потому что так."
      assert Sentenize.sentences(text) == ["Почему?", "Потому что так."]
    end

    test "exclamation splits" do
      text = "Внимание! Это важно."
      assert Sentenize.sentences(text) == ["Внимание!", "Это важно."]
    end

    test "number abbreviations don't split" do
      text = "Сумма 100 тыс. рублей была перечислена."
      result = Sentenize.sentences(text)
      assert length(result) == 1
    end

    test "г. (year) does not split" do
      text = "Договор от 15.01.2024 г. заключен между сторонами."
      result = Sentenize.sentences(text)
      assert length(result) == 1
    end

    test "empty text" do
      assert Sentenize.sentences("") == []
      assert Sentenize.sentences("   ") == []
    end

    test "single sentence without terminator" do
      assert Sentenize.sentences("Без точки") == ["Без точки"]
    end

    test "quotes don't cause false splits" do
      text = ~s(Ответчик заявил: «Я не согласен». Суд принял решение.)
      result = Sentenize.sentences(text)
      assert length(result) == 2
    end

    test "legal corpus sentence count" do
      text =
        File.read!(Path.join([__DIR__, "..", "fixtures", "001_penalty_late_delivery.txt"]))

      result = Sentenize.sentences(text)
      assert length(result) > 10
    end
  end

  describe "sentenize/1 with positions" do
    test "returns substrings with start/stop" do
      text = "Первое. Второе."
      [s1, s2] = Sentenize.sentenize(text)
      assert s1.text == "Первое."
      assert s2.text == "Второе."
      assert s1.start == 0
      assert s2.start > s1.stop
    end
  end
end
