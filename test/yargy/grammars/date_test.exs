defmodule Yargy.Grammars.DateTest do
  use ExUnit.Case, async: true

  alias Yargy.Grammars.Date, as: DateGrammar

  test "extracts dot-separated date" do
    dates = DateGrammar.extract("Договор заключен 15.03.2024")

    assert length(dates) == 1
    date = hd(dates)
    assert date.day == 15
    assert date.month == 3
    assert date.year == 2024
  end

  test "extracts written date with genitive month" do
    dates = DateGrammar.extract("15 марта 2024 года")

    assert length(dates) == 1
    date = hd(dates)
    assert date.day == 15
    assert date.month == 3
    assert date.year == 2024
  end

  test "extracts written date with г." do
    dates = DateGrammar.extract("от 1 января 2025 г.")

    assert length(dates) == 1
    date = hd(dates)
    assert date.day == 1
    assert date.month == 1
    assert date.year == 2025
  end

  test "extracts multiple dates" do
    text = "С 01.01.2024 по 31.12.2024"
    dates = DateGrammar.extract(text)

    assert length(dates) == 2
    years = Enum.map(dates, & &1.year)
    assert years == [2024, 2024]
  end

  test "does not match non-dates" do
    dates = DateGrammar.extract("Телефон: 8-800-555-35-35")
    assert dates == []
  end
end
