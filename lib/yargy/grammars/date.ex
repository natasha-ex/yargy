defmodule Yargy.Grammars.Date do
  @moduledoc """
  Grammar for extracting dates from Russian legal text.

  Matches patterns like:
  - "01.01.2025"
  - "1 января 2025 г."
  - "01 января 2025 года"
  - "15.03.2024 г."
  """

  alias Yargy.{Parser, Predicate, Rule, Tokenizer}

  @months_nominative %{
    "январь" => 1,
    "февраль" => 2,
    "март" => 3,
    "апрель" => 4,
    "май" => 5,
    "июнь" => 6,
    "июль" => 7,
    "август" => 8,
    "сентябрь" => 9,
    "октябрь" => 10,
    "ноябрь" => 11,
    "декабрь" => 12
  }

  @months_genitive %{
    "января" => 1,
    "февраля" => 2,
    "марта" => 3,
    "апреля" => 4,
    "мая" => 5,
    "июня" => 6,
    "июля" => 7,
    "августа" => 8,
    "сентября" => 9,
    "октября" => 10,
    "ноября" => 11,
    "декабря" => 12
  }

  @all_month_forms Map.merge(@months_nominative, @months_genitive)

  def parser do
    Parser.new(date_rule())
  end

  def date_rule do
    dot_date = dot_date_rule()
    written_date = written_date_rule()

    Rule.or_rule([dot_date, written_date])
    |> Rule.named("Date")
  end

  defp dot_date_rule do
    day = Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.lte(31))])
    dot = Rule.rule([Predicate.eq(".")])
    month = Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.lte(12))])
    year = Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.gte(1900))])

    year_suffix = Rule.optional(Rule.rule([Predicate.in_caseless(~w(г года г.))]))

    Rule.rule([[day, dot, month, dot, year, year_suffix]])
  end

  defp written_date_rule do
    day = Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.lte(31))])
    month_names = Map.keys(@all_month_forms)
    month = Rule.rule([Predicate.in_caseless(month_names)])
    year = Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.gte(1900))])

    year_suffix = Rule.optional(Rule.rule([Predicate.in_caseless(~w(г года г.))]))

    Rule.rule([[day, month, year, year_suffix]])
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
      numbers = Enum.filter(values, &Regex.match?(~r/^\d+$/, &1))
      day = numbers |> hd() |> String.to_integer()
      month = month_number(month_name)
      year = numbers |> Enum.find(&(String.to_integer(&1) >= 1900)) |> to_int()
      %{day: day, month: month, year: year}
    else
      numbers = Enum.filter(values, &Regex.match?(~r/^\d+$/, &1))

      case numbers do
        [d, m, y | _] ->
          %{day: String.to_integer(d), month: String.to_integer(m), year: String.to_integer(y)}

        _ ->
          %{day: nil, month: nil, year: nil}
      end
    end
  end

  defp month_number(name), do: Map.get(@all_month_forms, String.downcase(name))

  defp to_int(nil), do: nil
  defp to_int(s), do: String.to_integer(s)
end
