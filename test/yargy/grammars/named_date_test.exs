defmodule Yargy.Grammars.NamedDateTest do
  use ExUnit.Case

  alias Yargy.Grammars.NamedDate

  describe "extract/1" do
    test "15 января 2024 года" do
      results = NamedDate.extract("Договор от 15 января 2024 года")
      assert [%{day: 15, month: 1, year: 2024}] = results
    end

    test "1 марта 2023 г." do
      results = NamedDate.extract("Дата подачи: 1 марта 2023 г.")
      assert [%{day: 1, month: 3, year: 2023}] = results
    end

    test "25 декабря 2025" do
      results = NamedDate.extract("Срок до 25 декабря 2025")
      assert [%{day: 25, month: 12, year: 2025}] = results
    end

    test "multiple dates" do
      text = "Договор от 10 февраля 2024 года расторгнут 5 июня 2024 года"
      results = NamedDate.extract(text)
      assert length(results) == 2
      assert hd(results).month == 2
      assert List.last(results).month == 6
    end

    test "inflected month names" do
      results = NamedDate.extract("Оплата произведена 3 сентября 2024 года")
      assert [%{month: 9}] = results
    end
  end
end
