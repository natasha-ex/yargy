defmodule Yargy.Relations do
  @moduledoc """
  Grammatical agreement relations for constraining parse matches.

  Relations check that tokens within a match share compatible morphological
  properties (gender, number, case). When a relation is attached to multiple
  predicates, only matches where all related tokens agree are accepted.

  ## Grammeme groups

  - Gender: `masc`, `femn`, `neut`, `ms-f` (common gender), `GNdr` (fixed)
  - Number: `sing`, `plur`, `Sgtm` (singularia tantum), `Pltm` (pluralia tantum)
  - Case: `nomn`, `gent`, `datv`, `accs`, `ablt`, `loct`, `voct`, `gen2`, `acc2`, `loc2`, `Fixd`
  """

  @gender_tags MapSet.new(~w(masc femn neut ms-f GNdr))
  @number_tags MapSet.new(~w(sing plur Sgtm Pltm))
  @case_tags MapSet.new(~w(nomn gent datv accs ablt loct voct gen2 acc2 loc2 Fixd))

  @doc "Checks gender agreement between two form grammeme sets."
  def gender_agrees?(form1, form2) do
    g1 = extract(form1, @gender_tags)
    g2 = extract(form2, @gender_tags)

    if MapSet.member?(g1, "GNdr") or MapSet.member?(g2, "GNdr"), do: true, else: do_gender(g1, g2)
  end

  defp do_gender(g1, g2) do
    both_plural = MapSet.member?(g1, "plur") and MapSet.member?(g2, "plur")
    if both_plural, do: true, else: gender_match?(g1, g2)
  end

  defp gender_match?(g1, g2) do
    direct = not MapSet.disjoint?(MapSet.intersection(g1, g2), MapSet.new(~w(masc femn neut)))

    bi1 =
      MapSet.member?(g1, "ms-f") and (MapSet.member?(g2, "masc") or MapSet.member?(g2, "femn"))

    bi2 =
      MapSet.member?(g2, "ms-f") and (MapSet.member?(g1, "masc") or MapSet.member?(g1, "femn"))

    direct or bi1 or bi2
  end

  @doc "Checks number agreement between two form grammeme sets."
  def number_agrees?(form1, form2) do
    n1 = extract(form1, @number_tags)
    n2 = extract(form2, @number_tags)

    sing1 = MapSet.member?(n1, "sing") or MapSet.member?(n1, "Sgtm")
    sing2 = MapSet.member?(n2, "sing") or MapSet.member?(n2, "Sgtm")
    plur1 = MapSet.member?(n1, "plur") or MapSet.member?(n1, "Pltm")
    plur2 = MapSet.member?(n2, "plur") or MapSet.member?(n2, "Pltm")

    (sing1 and sing2) or (plur1 and plur2)
  end

  @doc "Checks case agreement between two form grammeme sets."
  def case_agrees?(form1, form2) do
    c1 = extract(form1, @case_tags)
    c2 = extract(form2, @case_tags)

    if MapSet.member?(c1, "Fixd") or MapSet.member?(c2, "Fixd") do
      true
    else
      not MapSet.disjoint?(c1, c2)
    end
  end

  @doc "Checks gender + number + case agreement."
  def gnc_agrees?(form1, form2) do
    gender_agrees?(form1, form2) and number_agrees?(form1, form2) and case_agrees?(form1, form2)
  end

  @doc """
  Validates a match against its relations.

  Returns `true` if all relation constraints are satisfied,
  filtering token forms to only compatible ones.
  """
  def validate_match(tokens_with_relations) do
    groups = group_by_relation(tokens_with_relations)

    Enum.all?(groups, fn {relation_fn, group_tokens} ->
      validate_group(relation_fn, group_tokens)
    end)
  end

  defp extract(grams, tag_set), do: MapSet.intersection(grams, tag_set)

  defp group_by_relation(tokens_with_relations) do
    tokens_with_relations
    |> Enum.group_by(fn {rel_id, _token} -> rel_id end, fn {_rel_id, token} -> token end)
  end

  defp validate_group(relation_fn, tokens) when length(tokens) < 2, do: relation_fn && true

  defp validate_group(relation_fn, tokens) do
    pairs = for a <- tokens, b <- tokens, a != b, do: {a, b}
    Enum.all?(pairs, &forms_agree?(relation_fn, &1))
  end

  defp forms_agree?(relation_fn, {a, b}) do
    a_forms = token_grams(a)
    b_forms = token_grams(b)

    Enum.any?(a_forms, fn af ->
      Enum.any?(b_forms, fn bf -> relation_fn.(af, bf) end)
    end)
  end

  defp token_grams(token) do
    case token.forms do
      [] -> [token_fallback_grams(token)]
      forms -> Enum.map(forms, & &1.grams)
    end
  end

  defp token_fallback_grams(_token), do: MapSet.new()
end
