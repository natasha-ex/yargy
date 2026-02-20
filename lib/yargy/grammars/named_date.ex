defmodule Yargy.Grammars.NamedDate do
  @moduledoc """
  Grammar for extracting dates with month names from Russian text.

  Uses morphological analysis and interpretation to extract structured dates like:
  - "15 января 2024 года" → %{day: 15, month: 1, year: 2024}
  - "1 марта 2023 г." → %{day: 1, month: 3, year: 2023}
  """

  alias Yargy.Interpretation.{Fact, Spec}
  alias Yargy.{Parser, Pipeline, Predicate, Rule}
  alias Yargy.Parser.Match

  @months %{
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

  @month_lemmas Map.keys(@months)

  def schema do
    Fact.define("Date", [:day, :month, :year])
  end

  def parser do
    Parser.new(date_rule())
  end

  def date_rule do
    s = schema()
    months = @months

    day =
      Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.lte(31))])
      |> Rule.interpretation(Spec.attr_custom(s, :day, &String.to_integer/1))

    month =
      Rule.rule([Predicate.and_(Predicate.gram("NOUN"), Predicate.normalized_in(@month_lemmas))])
      |> Rule.interpretation(Spec.attr_normalized_custom(s, :month, &Map.get(months, &1)))

    year =
      Rule.rule([Predicate.and_(Predicate.type(:int), Predicate.gte(1900))])
      |> Rule.interpretation(Spec.attr_custom(s, :year, &String.to_integer/1))

    year_suffix =
      Rule.optional(
        Rule.rule([Predicate.or_([Predicate.caseless("года"), Predicate.caseless("г")])])
      )

    optional_dot = Rule.optional(Rule.rule([Predicate.eq(".")]))

    Rule.rule([[day, month, year, year_suffix, optional_dot]])
    |> Rule.interpretation(Spec.fact(s))
    |> Rule.named("NamedDate")
  end

  @doc "Extracts dates with month names from text."
  def extract(text) do
    tokens = Pipeline.morph_tokenize(text)
    matches = Parser.findall(parser(), tokens)
    Enum.map(matches, &extract_date/1)
  end

  defp extract_date(match) do
    fact = Match.fact(match)
    {start_pos, stop_pos} = Match.span(match)

    %{
      day: Fact.get(fact, :day),
      month: Fact.get(fact, :month),
      year: Fact.get(fact, :year),
      text: Match.text(match),
      span: {start_pos, stop_pos}
    }
  end
end
