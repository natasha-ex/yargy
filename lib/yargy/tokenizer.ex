defmodule Yargy.Tokenizer do
  @moduledoc """
  Tokenizer that produces Yargy tokens with type and position information.
  """

  alias Yargy.Token

  @word_re ~r/[А-Яа-яЁёA-Za-z]+/u
  @int_re ~r/[0-9]+/
  @punct_re ~r/[^\s\w]/u

  @doc "Tokenizes text into a list of Yargy tokens with positions."
  def tokenize(text) do
    scan(text, 0, [])
    |> Enum.reverse()
  end

  defp scan("", _pos, acc), do: acc

  defp scan(text, pos, acc) do
    case match_whitespace(text) do
      {match, byte_len} ->
        char_len = String.length(match)
        rest = binary_part(text, byte_len, byte_size(text) - byte_len)
        scan(rest, pos + char_len, acc)

      nil ->
        scan_token(text, pos, acc)
    end
  end

  defp scan_token(text, pos, acc) do
    case match_token(text) do
      {match, byte_len, type} ->
        char_len = String.length(match)
        token = Token.new(match, type, pos, pos + char_len)
        rest = binary_part(text, byte_len, byte_size(text) - byte_len)
        scan(rest, pos + char_len, [token | acc])

      nil ->
        <<_::utf8, rest::binary>> = text
        scan(rest, pos + 1, acc)
    end
  end

  defp match_whitespace(text) do
    case Regex.run(~r/\A\s+/u, text, return: :index) do
      [{0, byte_len} | _] -> {binary_part(text, 0, byte_len), byte_len}
      _ -> nil
    end
  end

  defp match_token(text) do
    match_typed(text, @word_re, :word) ||
      match_typed(text, @int_re, :int) ||
      match_typed(text, @punct_re, :punct)
  end

  defp match_typed(text, re, type) do
    case match_re(re, text) do
      {match, byte_len} -> {match, byte_len, type}
      nil -> nil
    end
  end

  defp match_re(re, text) do
    case Regex.run(re, text, return: :index) do
      [{0, byte_len} | _] -> {binary_part(text, 0, byte_len), byte_len}
      _ -> nil
    end
  end
end
