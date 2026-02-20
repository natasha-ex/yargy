defmodule Yargy.Grammars.AmountTest do
  use ExUnit.Case, async: true

  alias Yargy.Grammars.Amount

  test "extracts simple amount" do
    amounts = Amount.extract("Сумма неустойки составляет 500000 руб.")

    assert length(amounts) == 1
    amt = hd(amounts)
    assert amt.amount == 500_000
    assert amt.currency == "RUB"
  end

  test "extracts amount in roubles with full word" do
    amounts = Amount.extract("взыскать 1500000 рублей")

    assert length(amounts) == 1
    assert hd(amounts).amount == 1_500_000
    assert hd(amounts).currency == "RUB"
  end

  test "extracts from real pretenziya" do
    text =
      File.read!(Path.join([__DIR__, "..", "..", "fixtures", "001_penalty_late_delivery.txt"]))

    amounts = Amount.extract(text)

    assert amounts != []
    currencies = Enum.map(amounts, & &1.currency) |> Enum.uniq()
    assert "RUB" in currencies
  end
end
