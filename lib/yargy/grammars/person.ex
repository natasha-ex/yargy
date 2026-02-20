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

  alias Yargy.{Parser, Pipeline, Predicate, Rule}

  def parser do
    Parser.new(person_rule())
  end

  def person_rule do
    Rule.or_rule([
      full_name_surn_first(),
      full_name_name_first(),
      initials_after_surname(),
      initials_before_surname()
    ])
    |> Rule.named("Person")
  end

  defp surname,
    do: Rule.rule([Predicate.and_(Predicate.gram("Surn"), Predicate.capitalized?())])

  defp first_name,
    do: Rule.rule([Predicate.and_(Predicate.gram("Name"), Predicate.capitalized?())])

  defp patronymic,
    do: Rule.rule([Predicate.and_(Predicate.gram("Patr"), Predicate.capitalized?())])

  defp dot, do: Rule.rule([Predicate.eq(".")])

  defp initial do
    Rule.rule([
      Predicate.and_([
        Predicate.type(:word),
        Predicate.upper?(),
        Predicate.length_eq(1)
      ])
    ])
  end

  defp initial_with_dot, do: Rule.rule([[initial(), dot()]])
  defp optional_patronymic, do: Rule.optional(patronymic())

  defp full_name_surn_first do
    Rule.rule([[surname(), first_name(), optional_patronymic()]])
  end

  defp full_name_name_first do
    Rule.rule([[first_name(), optional_patronymic(), surname()]])
  end

  defp initials_after_surname do
    Rule.rule([[surname(), initial_with_dot(), initial_with_dot()]])
  end

  defp initials_before_surname do
    Rule.rule([[initial_with_dot(), initial_with_dot(), surname()]])
  end

  @doc "Extracts person names from text using morphological analysis."
  def extract(text) do
    tokens = Pipeline.morph_tokenize(text)
    matches = Parser.findall(parser(), tokens)
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
