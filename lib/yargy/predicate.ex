defmodule Yargy.Predicate do
  @moduledoc """
  Token predicates — functions that test whether a token matches a condition.

  Port of Yargy's predicate bank. Each predicate is a function Token.t() -> boolean().
  Predicates compose: `and_(p1, p2)`, `or_(p1, p2)`, `not_(p)`.
  """

  alias Yargy.Token

  @type t :: (Token.t() -> boolean())

  @doc "Always matches."
  def true_, do: fn _token -> true end

  @doc "Exact value match."
  def eq(value), do: fn token -> token.value == value end

  @doc "Case-insensitive value match."
  def caseless(value) do
    downcased = String.downcase(value)
    fn token -> String.downcase(token.value) == downcased end
  end

  @doc "Value is in the given set."
  def in_(values) when is_list(values), do: in_(MapSet.new(values))

  def in_(%MapSet{} = values) do
    fn token -> MapSet.member?(values, token.value) end
  end

  @doc "Case-insensitive membership."
  def in_caseless(values) do
    downcased = MapSet.new(values, &String.downcase/1)
    fn token -> MapSet.member?(downcased, String.downcase(token.value)) end
  end

  @doc "Token type matches."
  def type(type), do: fn token -> token.type == type end

  @doc "Token value length equals n."
  def length_eq(n), do: fn token -> String.length(token.value) == n end

  @doc "Integer token >= value."
  def gte(value) do
    fn token ->
      token.type == :int and safe_int(token.value, 0) >= value
    end
  end

  @doc "Integer token <= value."
  def lte(value) do
    fn token ->
      token.type == :int and safe_int(token.value, value + 1) <= value
    end
  end

  defp safe_int(s, default) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> default
    end
  end

  @doc "Any morphological form has the given grammeme."
  def gram(grammeme) do
    fn token ->
      Enum.any?(token.forms, fn form ->
        MapSet.member?(form.grams, grammeme)
      end)
    end
  end

  @doc "Normalized form matches the given word."
  def normalized(word) do
    downcased = String.downcase(word)

    fn token ->
      Enum.any?(token.forms, fn form ->
        String.downcase(form.normalized) == downcased
      end)
    end
  end

  @doc "Normalized form is in the given dictionary."
  def dictionary(words) do
    downcased = MapSet.new(words, &String.downcase/1)

    fn token ->
      Enum.any?(token.forms, fn form ->
        MapSet.member?(downcased, String.downcase(form.normalized))
      end)
    end
  end

  @doc "Normalized form is in the given list of words."
  def normalized_in(words) when is_list(words) do
    downcased = MapSet.new(words, &String.downcase/1)

    fn token ->
      Enum.any?(token.forms, fn form ->
        MapSet.member?(downcased, String.downcase(form.normalized))
      end)
    end
  end

  @doc "First character is uppercase."
  def capitalized? do
    fn token ->
      case String.first(token.value) do
        nil -> false
        char -> String.upcase(char) == char and String.downcase(char) != char
      end
    end
  end

  @doc "All characters lowercase."
  def lower?, do: fn token -> String.downcase(token.value) == token.value end

  @doc "All characters uppercase."
  def upper?, do: fn token -> String.upcase(token.value) == token.value end

  @doc "Title case (first char upper, rest lower)."
  def title? do
    fn token ->
      case String.graphemes(token.value) do
        [first | rest] ->
          String.upcase(first) == first and
            Enum.all?(rest, &(String.downcase(&1) == &1))

        _ ->
          false
      end
    end
  end

  @doc "Logical AND of predicates."
  def and_(p1, p2) do
    fn token -> p1.(token) and p2.(token) end
  end

  def and_(predicates) when is_list(predicates) do
    fn token -> Enum.all?(predicates, & &1.(token)) end
  end

  @doc "Logical OR of predicates."
  def or_(p1, p2) do
    fn token -> p1.(token) or p2.(token) end
  end

  def or_(predicates) when is_list(predicates) do
    fn token -> Enum.any?(predicates, & &1.(token)) end
  end

  @doc "Logical NOT."
  def not_(predicate) do
    fn token -> not predicate.(token) end
  end

  @doc "Custom predicate from a function."
  def custom(func), do: func
end
