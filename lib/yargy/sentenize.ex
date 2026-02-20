defmodule Yargy.Sentenize do
  @moduledoc """
  Rule-based sentence segmentation for Russian text.

  Port of razdel's sentenizer. Finds potential split points (sentence-ending
  punctuation) and applies rules to decide whether to actually split.
  Handles abbreviations, initials, bullets, quotes, brackets, dashes.
  """

  @endings String.graphemes(".?!…")
  @dashes String.graphemes("‑–—−-")
  @close_quotes String.graphemes("»\u201D\u2019")
  @generic_quotes String.graphemes("\"\u201E'")
  @close_brackets String.graphemes(")]}")
  @all_quotes MapSet.new(@close_quotes ++ @generic_quotes ++ String.graphemes("«\"\u2018"))
  @smiles ~r/[=:;]-?[)(]{1,3}/

  @delimiters_chars @endings ++ [";"] ++ @generic_quotes ++ @close_quotes ++ @close_brackets
  @delimiters_pattern Regex.compile!(
                        "(" <>
                          Regex.source(@smiles) <>
                          "|[" <> Regex.escape(Enum.join(@delimiters_chars)) <> "])",
                        "u"
                      )

  @head_sokrs MapSet.new(~w(
    букв ст трад лат венг исп кат укр нем англ фр итал греч
    евр араб яп слав кит рус русск латв словацк хорв
    mr mrs ms dr vs св арх зав зам проф акад кн корр ред гр ср
    чл им тов нач пол chap п пп ч чч гл стр абз пт no
    просп пр ул ш г гор д к корп пер обл эт пом ауд оф ком комн каб
    домовлад лит т рп пос с х пл bd о оз р а
    обр ум ок откр пс ps upd см напр доп юр физ тел сб внутр
    дифф гос отм
  ))

  @sokrs MapSet.new(~w(
    дес тыс млн млрд дол долл коп руб р проц га барр куб кв км см
    час мин сек в вв г гг с стр co corp inc изд ed др al
    сокр рис искл прим яз устар шутл
  ) ++ MapSet.to_list(@head_sokrs))

  @head_pair_sokrs MapSet.new([
                     {"т", "е"},
                     {"т", "к"},
                     {"т", "н"},
                     {"и", "о"},
                     {"к", "н"},
                     {"к", "п"},
                     {"п", "н"},
                     {"к", "т"},
                     {"л", "д"}
                   ])

  @pair_sokrs MapSet.new(
                [
                  {"т", "п"},
                  {"т", "д"},
                  {"у", "е"},
                  {"н", "э"},
                  {"p", "m"},
                  {"a", "m"},
                  {"с", "г"},
                  {"р", "х"},
                  {"с", "ш"},
                  {"з", "д"},
                  {"л", "с"},
                  {"ч", "т"},
                  {"ед", "ч"},
                  {"мн", "ч"},
                  {"повел", "накл"},
                  {"муж", "р"},
                  {"жен", "р"}
                ] ++ MapSet.to_list(@head_pair_sokrs)
              )

  @initials MapSet.new(~w(дж ed вс))

  @word_re ~r/([^\W\d]+|\d+)/u
  @first_token_re ~r/^\s*([^\W\d]+|\d+|[^\w\s])/u
  @last_token_re ~r/([^\W\d]+|\d+|[^\w\s])\s*$/u
  @pair_sokr_re ~r/(\w)\s*\.\s*(\w)\s*$/u
  @token_re ~r/([^\W\d]+|\d+|[^\w\s])/u
  @roman_re ~r/^[IVXML]+$/u

  @bullet_chars MapSet.new(~w(§ а б в г д е a b c d e f))
  @bullet_bounds MapSet.new(~w(. \)))
  @bullet_size 20

  @window 10

  defmodule Substring do
    @moduledoc false
    defstruct [:start, :stop, :text]
  end

  @doc "Splits text into sentences, returning `[%Substring{start, stop, text}]`."
  def sentenize(text) when is_binary(text) do
    text
    |> split_at_delimiters()
    |> join_by_rules()
    |> find_substrings(text)
  end

  @doc "Splits text into sentence strings."
  def sentences(text) when is_binary(text) do
    text
    |> sentenize()
    |> Enum.map(& &1.text)
  end

  defp split_at_delimiters(text) do
    text = String.trim(text)
    if text == "", do: [], else: do_split(text)
  end

  defp do_split(text) do
    matches = Regex.scan(@delimiters_pattern, text, return: :index)

    case matches do
      [] ->
        [{:chunk, text}]

      _ ->
        build_parts(text, matches, 0, [])
    end
  end

  defp build_parts(text, [], prev, acc) do
    rest = binary_part(text, prev, byte_size(text) - prev)
    Enum.reverse([{:chunk, rest} | acc])
  end

  defp build_parts(text, [[{start, len} | _] | rest_matches], prev, acc) do
    before = binary_part(text, prev, start - prev)
    delimiter = binary_part(text, start, len)
    stop = start + len

    left = safe_slice_before(text, start, @window)
    right = safe_slice_after(text, stop, @window)

    split = %{left: left, delimiter: delimiter, right: right}

    acc = [{:split, split}, {:chunk, before} | acc]
    build_parts(text, rest_matches, stop, acc)
  end

  defp safe_slice_before(text, byte_pos, window) do
    prefix = binary_part(text, 0, byte_pos)
    chars = String.graphemes(prefix)
    taken = Enum.take(chars, -window)
    Enum.join(taken)
  end

  defp safe_slice_after(text, byte_pos, window) do
    suffix = binary_part(text, byte_pos, byte_size(text) - byte_pos)
    suffix |> String.graphemes() |> Enum.take(window) |> Enum.join()
  end

  defp join_by_rules(parts) do
    do_join(parts, nil, [])
  end

  defp do_join([], nil, acc), do: Enum.reverse(acc)

  defp do_join([], buffer, acc), do: Enum.reverse([buffer | acc])

  defp do_join([{:chunk, text} | rest], nil, acc) do
    do_join(rest, text, acc)
  end

  defp do_join([{:split, split}, {:chunk, right} | rest], buffer, acc) do
    split = Map.put(split, :buffer, buffer || "")

    if should_join?(split) do
      do_join(rest, (buffer || "") <> split.delimiter <> right, acc)
    else
      do_join(rest, right, [(buffer || "") <> split.delimiter | acc])
    end
  end

  defp do_join([{:split, split} | rest], buffer, acc) do
    do_join(rest, (buffer || "") <> split.delimiter, acc)
  end

  defp do_join([{:chunk, text} | rest], buffer, acc) do
    do_join(rest, (buffer || "") <> text, acc)
  end

  defp should_join?(split) do
    rules = [
      &empty_side/1,
      &no_space_prefix/1,
      &lower_right/1,
      &delimiter_right/1,
      &sokr_left/1,
      &inside_pair_sokr/1,
      &initials_left/1,
      &list_item/1,
      &close_quote/1,
      &close_bracket/1,
      &dash_right/1
    ]

    Enum.find_value(rules, fn rule ->
      case rule.(split) do
        :join -> true
        :split -> false
        nil -> nil
      end
    end) || false
  end

  defp empty_side(split) do
    lt = left_token(split.left)
    rt = right_token(split.right)
    if lt == nil or rt == nil, do: :join
  end

  defp no_space_prefix(split) do
    unless Regex.match?(~r/^\s/u, split.right), do: :join
  end

  defp lower_right(split) do
    case right_token(split.right) do
      nil -> nil
      t -> if lower_alpha?(t), do: :join
    end
  end

  defp delimiter_right(split) do
    rt = right_token(split.right)

    cond do
      rt in @generic_quotes -> nil
      rt != nil and rt in @delimiters_chars -> :join
      Regex.match?(~r/^\s*#{Regex.source(@smiles)}/u, split.right) -> :join
      true -> nil
    end
  end

  defp sokr_left(%{delimiter: d}) when d != ".", do: nil

  defp sokr_left(split) do
    rt = right_token(split.right)
    lt = left_token(split.left)

    cond do
      rt == nil or lt == nil ->
        nil

      left_pair_sokr?(split.left) ->
        check_pair_sokr(split.left, lt, rt)

      true ->
        check_single_sokr(lt, rt)
    end
  end

  defp check_pair_sokr(left_text, lt, rt) do
    {a, b} = left_pair_sokr(left_text)
    pair = {String.downcase(a), String.downcase(b)}

    cond do
      MapSet.member?(@head_pair_sokrs, pair) -> :join
      MapSet.member?(@pair_sokrs, pair) and sokr_token?(rt) -> :join
      MapSet.member?(@pair_sokrs, pair) -> nil
      true -> check_single_sokr(lt, rt)
    end
  end

  defp check_single_sokr(lt, rt) do
    left_lower = String.downcase(lt)

    cond do
      MapSet.member?(@head_sokrs, left_lower) -> :join
      MapSet.member?(@sokrs, left_lower) and sokr_token?(rt) -> :join
      true -> nil
    end
  end

  defp inside_pair_sokr(%{delimiter: d}) when d != ".", do: nil

  defp inside_pair_sokr(split) do
    lt = left_token(split.left)
    rt = right_token(split.right)

    if lt && rt do
      pair = {String.downcase(lt), String.downcase(rt)}
      if MapSet.member?(@pair_sokrs, pair), do: :join
    end
  end

  defp initials_left(%{delimiter: d}) when d != ".", do: nil

  defp initials_left(split) do
    lt = left_token(split.left)

    cond do
      lt == nil ->
        nil

      String.length(lt) == 1 and Regex.match?(~r/^\p{L}$/u, lt) and String.upcase(lt) == lt ->
        :join

      MapSet.member?(@initials, String.downcase(lt)) ->
        :join

      true ->
        nil
    end
  end

  defp close_quote(split) do
    d = split.delimiter

    cond do
      not MapSet.member?(@all_quotes, d) ->
        nil

      d in @close_quotes ->
        close_bound(split)

      d in @generic_quotes ->
        if Regex.match?(~r/\s$/u, split.left), do: :join, else: close_bound(split)

      true ->
        nil
    end
  end

  defp close_bracket(split) do
    if split.delimiter in @close_brackets do
      close_bound(split)
    end
  end

  defp close_bound(split) do
    lt = left_token(split.left)
    if lt && lt in @endings, do: nil, else: :join
  end

  defp list_item(split) do
    if MapSet.member?(@bullet_bounds, split.delimiter) do
      check_bullet_buffer(split.buffer || "")
    end
  end

  defp check_bullet_buffer(buffer) do
    if String.length(buffer) <= @bullet_size do
      buffer_tokens = Regex.scan(@token_re, buffer) |> Enum.map(&hd/1)
      if Enum.all?(buffer_tokens, &bullet?/1), do: :join
    end
  end

  defp dash_right(split) do
    rt = right_token(split.right)

    if rt && rt in @dashes do
      rw = right_word(split.right)
      if rw && lower_alpha?(rw), do: :join
    end
  end

  defp left_token(text) do
    case Regex.run(@last_token_re, text) do
      [_, token] -> token
      _ -> nil
    end
  end

  defp right_token(text) do
    case Regex.run(@first_token_re, text) do
      [_, token] -> token
      _ -> nil
    end
  end

  defp right_word(text) do
    case Regex.run(@word_re, text) do
      [_, word] -> word
      _ -> nil
    end
  end

  defp left_pair_sokr?(text), do: Regex.match?(@pair_sokr_re, text)

  defp left_pair_sokr(text) do
    case Regex.run(@pair_sokr_re, text) do
      [_, a, b] -> {a, b}
      _ -> nil
    end
  end

  defp sokr_token?(token) do
    cond do
      Regex.match?(~r/^\d+$/, token) -> true
      not Regex.match?(~r/^\w+$/u, token) -> true
      String.downcase(token) == token -> true
      true -> false
    end
  end

  defp bullet?(token) do
    cond do
      Regex.match?(~r/^\d+$/, token) -> true
      MapSet.member?(@bullet_bounds, token) -> true
      MapSet.member?(@bullet_chars, String.downcase(token)) -> true
      Regex.match?(@roman_re, token) -> true
      true -> false
    end
  end

  defp lower_alpha?(token) do
    Regex.match?(~r/^[^\W\d]+$/u, token) and String.downcase(token) == token
  end

  defp find_substrings(chunks, text) do
    chunks
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> do_find_substrings(text, 0, [])
  end

  defp do_find_substrings([], _text, _offset, acc), do: Enum.reverse(acc)

  defp do_find_substrings([chunk | rest], text, offset, acc) do
    case :binary.match(text, chunk, scope: {offset, byte_size(text) - offset}) do
      {start, len} ->
        sub = %Substring{start: start, stop: start + len, text: chunk}
        do_find_substrings(rest, text, start + len, [sub | acc])

      :nomatch ->
        do_find_substrings(rest, text, offset, acc)
    end
  end
end
