defmodule Yargy.Grammars.Amount do
  @moduledoc """
  Grammar for extracting monetary amounts from Russian legal text.

  Matches patterns like:
  - "500 000 руб."
  - "1 500 000 рублей"
  - "2 500 000 (два миллиона пятьсот тысяч) рублей"
  - "100 000,00 руб."
  """

  use Yargy.Grammar

  alias Yargy.{Parser, Tokenizer}

  @currency_words ~w(
    рублей рубля рубль руб
    долларов доллара доллар
    евро
  )

  defrule(:number, integer())
  defrule(:numbers, repeat(rule(:number)))
  defrule(:kopecks, optional(token(",") ~> integer()))
  defrule(:currency, caseless(@currency_words))
  defrule(:optional_dot, optional(token(".")))

  defgrammar(
    :amount,
    rule(:numbers) ~> rule(:kopecks) ~> rule(:currency) ~> rule(:optional_dot)
  )

  def parser, do: amount_parser()

  def amount_rule, do: amount_parser().rule

  @doc "Extracts monetary amounts from text."
  def extract(text) do
    tokens = Tokenizer.tokenize(text)
    matches = Parser.findall(amount_parser(), tokens)
    Enum.map(matches, &extract_amount/1)
  end

  defp extract_amount(match) do
    token_values = Enum.map(match.tokens, & &1.value)
    {start_pos, stop_pos} = Parser.Match.span(match)

    currency_idx =
      Enum.find_index(token_values, fn v ->
        String.downcase(v) in @currency_words
      end)

    {number_parts, currency_and_rest} =
      Enum.split(token_values, currency_idx || length(token_values))

    currency = if currency_and_rest != [], do: hd(currency_and_rest)

    amount = parse_amount(number_parts)

    %{
      text: Enum.join(token_values, " "),
      amount: amount,
      currency: normalize_currency(currency),
      span: {start_pos, stop_pos}
    }
  end

  defp parse_amount(parts) do
    parts
    |> Enum.reject(&(&1 == ","))
    |> Enum.join("")
    |> parse_number_string()
  end

  defp parse_number_string(""), do: nil

  defp parse_number_string(s) do
    if String.contains?(s, ",") do
      String.to_float(String.replace(s, ",", "."))
    else
      case Integer.parse(s) do
        {n, _} -> n
        :error -> nil
      end
    end
  end

  defp normalize_currency(nil), do: nil

  defp normalize_currency(word) do
    case String.downcase(word) do
      w when w in ~w(рублей рубля рубль руб) -> "RUB"
      w when w in ~w(долларов доллара доллар) -> "USD"
      "евро" -> "EUR"
      _ -> word
    end
  end
end
