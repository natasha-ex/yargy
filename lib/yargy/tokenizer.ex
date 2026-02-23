defmodule Yargy.Tokenizer do
  @moduledoc """
  Tokenizer that produces Yargy tokens with type and position information.

  Single-pass byte scanner — classifies each byte/codepoint and groups
  consecutive characters of the same class into tokens.
  """

  alias Yargy.Token

  @doc "Tokenizes text into a list of Yargy tokens with positions."
  def tokenize(text) when is_binary(text) do
    scan(text, 0, [])
  end

  defp scan(<<>>, _pos, acc), do: Enum.reverse(acc)

  defp scan(text, pos, acc) do
    case classify_first(text) do
      {:space, rest, byte_len} ->
        char_len = codepoint_count(text, byte_len)
        scan(rest, pos + char_len, acc)

      {:word, _rest, _byte_len} ->
        {value, rest, _byte_len} = consume_while(text, :word)
        char_len = String.length(value)
        token = Token.new(value, :word, pos, pos + char_len)
        scan(rest, pos + char_len, [token | acc])

      {:digit, _rest, _byte_len} ->
        {value, rest, byte_len} = consume_while(text, :digit)
        char_len = byte_len
        token = Token.new(value, :int, pos, pos + char_len)
        scan(rest, pos + char_len, [token | acc])

      {:punct, rest, byte_len} ->
        value = binary_part(text, 0, byte_len)
        token = Token.new(value, :punct, pos, pos + 1)
        scan(rest, pos + 1, [token | acc])

      {:other, rest, _byte_len} ->
        scan(rest, pos + 1, acc)
    end
  end

  defp consume_while(text, class) do
    consume_while(text, class, 0)
  end

  defp consume_while(text, class, byte_offset) do
    rest = binary_part(text, byte_offset, byte_size(text) - byte_offset)

    case classify_first(rest) do
      {^class, _rest, byte_len} ->
        consume_while(text, class, byte_offset + byte_len)

      _ ->
        value = binary_part(text, 0, byte_offset)
        rest = binary_part(text, byte_offset, byte_size(text) - byte_offset)
        {value, rest, byte_offset}
    end
  end

  # Cyrillic block: А-я (U+0410..U+044F), Ё (U+0401), ё (U+0451)
  # Latin: A-Z (0x41..0x5A), a-z (0x61..0x7A)

  defp classify_first(<<>>), do: nil

  # ASCII fast path
  defp classify_first(<<c, rest::binary>>) when c in ?A..?Z or c in ?a..?z,
    do: {:word, rest, 1}

  defp classify_first(<<c, rest::binary>>) when c in ?0..?9,
    do: {:digit, rest, 1}

  defp classify_first(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\r],
    do: {:space, rest, 1}

  # 2-byte UTF-8 Cyrillic (U+0401 Ё, U+0410..U+044F А-я, U+0451 ё)
  defp classify_first(<<0xD0, b, rest::binary>>) when b in 0x90..0xBF,
    do: {:word, rest, 2}

  defp classify_first(<<0xD1, b, rest::binary>>) when b in 0x80..0x8F,
    do: {:word, rest, 2}

  # Ё = D0 81, ё = D1 91
  defp classify_first(<<0xD0, 0x81, rest::binary>>), do: {:word, rest, 2}
  defp classify_first(<<0xD1, 0x91, rest::binary>>), do: {:word, rest, 2}

  # Whitespace: non-breaking space, other Unicode whitespace
  defp classify_first(<<0xC2, 0xA0, rest::binary>>), do: {:space, rest, 2}

  # General UTF-8: check if it's a letter
  defp classify_first(<<c::utf8, rest::binary>>) when c > 127 do
    byte_len = byte_size(<<c::utf8>>)

    cond do
      unicode_letter?(c) -> {:word, rest, byte_len}
      unicode_space?(c) -> {:space, rest, byte_len}
      true -> {:punct, rest, byte_len}
    end
  end

  # ASCII punctuation (anything else that's not whitespace/letter/digit)
  defp classify_first(<<_c, rest::binary>>), do: {:punct, rest, 1}

  defp unicode_letter?(c) do
    # Covers Latin extended, Cyrillic extended, Greek, etc.
    (c >= 0x00C0 and c <= 0x024F) or
      (c >= 0x0400 and c <= 0x04FF) or
      (c >= 0x0370 and c <= 0x03FF) or
      (c >= 0x0500 and c <= 0x052F) or
      (c >= 0x1E00 and c <= 0x1EFF)
  end

  defp unicode_space?(c) do
    c in [0x00A0, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006,
          0x2007, 0x2008, 0x2009, 0x200A, 0x200B, 0x2028, 0x2029, 0x202F,
          0x205F, 0x3000, 0xFEFF]
  end

  defp codepoint_count(binary, byte_len) do
    binary |> binary_part(0, byte_len) |> String.length()
  end
end
