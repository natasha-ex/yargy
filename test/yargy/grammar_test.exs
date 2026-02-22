defmodule Yargy.GrammarTest do
  use ExUnit.Case, async: true

  alias Yargy.{Parser, Tokenizer}

  # --- Grammar modules defined with the new DSL ---

  defmodule PersonGrammar do
    use Yargy.Grammar

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
  end

  defmodule AmountGrammar do
    use Yargy.Grammar

    defrule :number, integer()
    defrule :numbers, repeat(rule(:number))
    defrule :currency, caseless(~w[рублей рубля рубль руб долларов доллара доллар евро])
    defrule :optional_dot, optional(token("."))

    defgrammar :amount, rule(:numbers) ~> rule(:currency) ~> rule(:optional_dot)
  end

  defmodule DateGrammar do
    use Yargy.Grammar

    defrule :day, all([integer(), lte(31)])
    defrule :dot, token(".")
    defrule :month_num, all([integer(), lte(12)])
    defrule :year, all([integer(), gte(1900)])
    defrule :year_suffix, optional(caseless(~w[г года г.]))

    defrule :month_name, caseless(~w[
      января февраля марта апреля мая июня
      июля августа сентября октября ноября декабря
    ])

    defgrammar :date, choice([
      rule(:day) ~> rule(:dot) ~> rule(:month_num) ~> rule(:dot) ~> rule(:year) ~> rule(:year_suffix),
      rule(:day) ~> rule(:month_name) ~> rule(:year) ~> rule(:year_suffix)
    ])
  end

  # --- Person tests (same cases as Yargy.Grammars.PersonTest) ---

  describe "PersonGrammar" do
    test "Иванов Иван Петрович" do
      matches = PersonGrammar.person_text("Ответчик Иванов Иван Петрович не исполнил обязательства")
      assert [match] = matches
      assert Parser.Match.text(match) == "Иванов Иван Петрович"
    end

    test "Иван Петрович Иванов" do
      matches = PersonGrammar.person_text("Истцом является Иван Петрович Иванов")
      assert [match] = matches
      assert Parser.Match.text(match) == "Иван Петрович Иванов"
    end

    test "surname only with initials after" do
      matches = PersonGrammar.person_text("Подпись: Петров А.В.")
      assert [match] = matches
      assert Parser.Match.text(match) == "Петров А . В ."
    end

    test "initials before surname" do
      matches = PersonGrammar.person_text("Представитель А.В. Сидоров")
      assert [match] = matches
      assert Parser.Match.text(match) == "А . В . Сидоров"
    end

    test "multiple persons" do
      matches =
        PersonGrammar.person_text("Иванов Иван Петрович и Сидорова Мария Алексеевна подписали договор")

      assert length(matches) == 2
    end
  end

  # --- Amount tests (same cases as Yargy.Grammars.AmountTest) ---

  describe "AmountGrammar" do
    test "extracts simple amount" do
      tokens = Tokenizer.tokenize("Сумма неустойки составляет 500000 руб.")
      matches = AmountGrammar.amount(tokens)
      assert length(matches) == 1
    end

    test "extracts amount in roubles with full word" do
      tokens = Tokenizer.tokenize("взыскать 1500000 рублей")
      matches = AmountGrammar.amount(tokens)
      assert length(matches) == 1
    end

    test "extracts from real pretenziya" do
      text = File.read!(Path.join([__DIR__, "..", "fixtures", "001_penalty_late_delivery.txt"]))
      tokens = Tokenizer.tokenize(text)
      matches = AmountGrammar.amount(tokens)
      assert matches != []
    end
  end

  # --- Date tests (same cases as Yargy.Grammars.DateTest) ---

  describe "DateGrammar" do
    test "extracts dot-separated date" do
      tokens = Tokenizer.tokenize("Договор заключен 15.03.2024")
      matches = DateGrammar.date(tokens)
      assert length(matches) == 1
    end

    test "extracts written date with genitive month" do
      tokens = Tokenizer.tokenize("15 марта 2024 года")
      matches = DateGrammar.date(tokens)
      assert length(matches) == 1
    end

    test "extracts written date with г." do
      tokens = Tokenizer.tokenize("от 1 января 2025 г.")
      matches = DateGrammar.date(tokens)
      assert length(matches) == 1
    end

    test "extracts multiple dates" do
      tokens = Tokenizer.tokenize("С 01.01.2024 по 31.12.2024")
      matches = DateGrammar.date(tokens)
      assert length(matches) == 2
    end

    test "does not match non-dates" do
      tokens = Tokenizer.tokenize("Телефон: 8-800-555-35-35")
      matches = DateGrammar.date(tokens)
      assert matches == []
    end
  end

  # --- Compile-time caching ---

  describe "compile-time" do
    test "parser is pre-built (same reference on each call)" do
      p1 = PersonGrammar.person_parser()
      p2 = PersonGrammar.person_parser()
      assert p1 === p2
    end

    test "rule accessor returns named rule" do
      rule = PersonGrammar.surname_rule()
      assert rule.name == "surname"
    end
  end
end
