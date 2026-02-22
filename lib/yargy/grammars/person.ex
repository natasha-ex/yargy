defmodule Yargy.Grammars.Person do
  @moduledoc """
  Grammar for extracting person names from Russian text.

  Uses morphological analysis to identify surnames (Surn), first names (Name),
  and patronymics (Patr). Matches patterns like:
  - "Иванов Иван Петрович"
  - "Иван Петрович Иванов"
  - "Иванов И.П."
  - "И.П. Иванов"
  """

  use Yargy.Grammar

  alias Yargy.{Parser, Pipeline}

  defrule :surname, all([gram("Surn"), capitalized()])
  defrule :first_name, all([gram("Name"), capitalized()])
  defrule :patronymic, all([gram("Patr"), capitalized()])
  defrule :dot, token(".")
  defrule :initial, all([upper(), length_eq(1)])
  defrule :initial_dot, rule(:initial) ~> rule(:dot)

  defgrammar :person, choice([
    rule(:surname) ~> rule(:first_name) ~> optional(rule(:patronymic)),
    rule(:first_name) ~> optional(rule(:patronymic)) ~> rule(:surname),
    rule(:surname) ~> rule(:initial_dot) ~> rule(:initial_dot),
    rule(:initial_dot) ~> rule(:initial_dot) ~> rule(:surname)
  ])

  def parser, do: person_parser()

  def person_rule, do: person_parser().rule

  @doc "Extracts person names from text using morphological analysis."
  def extract(text) do
    tokens = Pipeline.morph_tokenize(text)
    matches = Parser.findall(person_parser(), tokens)
    Enum.map(matches, &extract_person/1)
  end

  defp extract_person(match) do
    token_values = Enum.map(match.tokens, & &1.value)
    {start_pos, stop_pos} = Parser.Match.span(match)

    %{
      text: Enum.join(token_values, " "),
      span: {start_pos, stop_pos}
    }
  end
end
