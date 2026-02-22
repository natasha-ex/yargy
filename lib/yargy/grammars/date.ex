defmodule Yargy.Grammars.Date do
  @moduledoc """
  Grammar for extracting dates from Russian legal text.

  Matches patterns like:
  - "01.01.2025"
  - "1 января 2025 г."
  - "01 января 2025 года"
  - "15.03.2024 г."
  """

  use Yargy.Grammar

  alias Yargy.{Parser, Tokenizer}

  @months_nominative %{
    "январь" => 1, "февраль" => 2, "март" => 3, "апрель" => 4,
    "май" => 5, "июнь" => 6, "июль" => 7, "август" => 8,
    "сентябрь" => 9, "октябрь" => 10, "ноябрь" => 11, "декабрь" => 12
  }

  @months_genitive %{
    "января" => 1, "февраля" => 2, "марта" => 3, "апреля" => 4,
    "мая" => 5, "июня" => 6, "июля" => 7, "августа" => 8,
    "сентября" => 9, "октября" => 10, "ноября" => 11, "декабря" => 12
  }

  @all_month_forms Map.merge(@months_nominative, @months_genitive)

  defrule :day, all([integer(), lte(31)])
  defrule :dot, token(".")
  defrule :month_num, all([integer(), lte(12)])
  defrule :year, all([integer(), gte(1900)])
  defrule :year_suffix, optional(caseless(~w[г года г.]))
  defrule :month_name, caseless(Map.keys(@all_month_forms))

  defgrammar :dot_date,
    rule(:day) ~> rule(:dot) ~> rule(:month_num) ~> rule(:dot) ~> rule(:year) ~> rule(:year_suffix)

  defgrammar :written_date,
    rule(:day) ~> rule(:month_name) ~> rule(:year) ~> rule(:year_suffix)

  def parser do
    Parser.new(date_rule())
  end

  def date_rule do
    Yargy.Rule.or_rule([dot_date_parser().rule, written_date_parser().rule])
    |> Yargy.Rule.named("Date")
  end

  @doc "Extracts dates from text."
  def extract(text) do
    tokens = Tokenizer.tokenize(text)
    matches = Parser.findall(parser(), tokens)
    Enum.map(matches, &extract_date/1)
  end

  defp extract_date(match) do
    token_values = Enum.map(match.tokens, & &1.value)
    {start_pos, stop_pos} = Parser.Match.span(match)

    date = parse_date(token_values)

    Map.merge(date, %{
      text: Enum.join(token_values, " "),
      span: {start_pos, stop_pos}
    })
  end

  defp parse_date(values) do
    month_name = Enum.find(values, &month_number/1)

    if month_name do
      numbers = Enum.filter(values, &digit_string?/1)
      day = numbers |> hd() |> String.to_integer()
      month = month_number(month_name)
      year = numbers |> Enum.find(&(String.to_integer(&1) >= 1900)) |> to_int()
      %{day: day, month: month, year: year}
    else
      numbers = Enum.filter(values, &digit_string?/1)

      case numbers do
        [d, m, y | _] ->
          %{day: String.to_integer(d), month: String.to_integer(m), year: String.to_integer(y)}

        _ ->
          %{day: nil, month: nil, year: nil}
      end
    end
  end

  defp month_number(name), do: Map.get(@all_month_forms, String.downcase(name))

  defp digit_string?(<<c, _::binary>>) when c >= ?0 and c <= ?9, do: true
  defp digit_string?(_), do: false

  defp to_int(nil), do: nil
  defp to_int(s), do: String.to_integer(s)
end
