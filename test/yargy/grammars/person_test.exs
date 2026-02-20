defmodule Yargy.Grammars.PersonTest do
  use ExUnit.Case

  alias Yargy.Grammars.Person

  describe "extract/1" do
    test "Иванов Иван Петрович" do
      results = Person.extract("Ответчик Иванов Иван Петрович не исполнил обязательства")
      assert [%{text: text}] = results
      assert text == "Иванов Иван Петрович"
    end

    test "Иван Петрович Иванов" do
      results = Person.extract("Истцом является Иван Петрович Иванов")
      assert [%{text: text}] = results
      assert text == "Иван Петрович Иванов"
    end

    test "surname only with initials after" do
      results = Person.extract("Подпись: Петров А.В.")
      assert [%{text: text}] = results
      assert text == "Петров А . В ."
    end

    test "initials before surname" do
      results = Person.extract("Представитель А.В. Сидоров")
      assert [%{text: text}] = results
      assert text == "А . В . Сидоров"
    end

    test "multiple persons" do
      results =
        Person.extract("Иванов Иван Петрович и Сидорова Мария Алексеевна подписали договор")

      assert length(results) == 2
    end
  end
end
