defmodule Yargy.RelationsTest do
  use ExUnit.Case

  alias Yargy.{Pipeline, Relations}

  defp tagged_token(word) do
    [token | _] = Pipeline.morph_tokenize(word)
    token
  end

  describe "gender_agrees?/2" do
    test "same gender agrees" do
      grams1 = MapSet.new(["masc", "sing", "nomn"])
      grams2 = MapSet.new(["masc", "sing", "nomn"])
      assert Relations.gender_agrees?(grams1, grams2)
    end

    test "different gender disagrees" do
      grams1 = MapSet.new(["masc", "sing", "nomn"])
      grams2 = MapSet.new(["femn", "sing", "nomn"])
      refute Relations.gender_agrees?(grams1, grams2)
    end

    test "ms-f agrees with masc" do
      grams1 = MapSet.new(["ms-f", "sing", "nomn"])
      grams2 = MapSet.new(["masc", "sing", "nomn"])
      assert Relations.gender_agrees?(grams1, grams2)
    end
  end

  describe "number_agrees?/2" do
    test "sing + sing" do
      assert Relations.number_agrees?(MapSet.new(["sing"]), MapSet.new(["sing"]))
    end

    test "plur + plur" do
      assert Relations.number_agrees?(MapSet.new(["plur"]), MapSet.new(["plur"]))
    end

    test "sing + plur disagrees" do
      refute Relations.number_agrees?(MapSet.new(["sing"]), MapSet.new(["plur"]))
    end

    test "Sgtm + sing agrees" do
      assert Relations.number_agrees?(MapSet.new(["Sgtm"]), MapSet.new(["sing"]))
    end
  end

  describe "case_agrees?/2" do
    test "same case" do
      assert Relations.case_agrees?(MapSet.new(["nomn"]), MapSet.new(["nomn"]))
    end

    test "different case" do
      refute Relations.case_agrees?(MapSet.new(["nomn"]), MapSet.new(["gent"]))
    end

    test "Fixd agrees with anything" do
      assert Relations.case_agrees?(MapSet.new(["Fixd"]), MapSet.new(["gent"]))
    end
  end

  describe "gnc_agrees?/2" do
    test "full agreement" do
      grams1 = MapSet.new(["masc", "sing", "datv"])
      grams2 = MapSet.new(["masc", "sing", "datv"])
      assert Relations.gnc_agrees?(grams1, grams2)
    end

    test "gender mismatch" do
      grams1 = MapSet.new(["masc", "sing", "datv"])
      grams2 = MapSet.new(["femn", "sing", "datv"])
      refute Relations.gnc_agrees?(grams1, grams2)
    end
  end

  describe "validate_match/1 with real tokens" do
    test "саше иванову agree" do
      t1 = tagged_token("саше")
      t2 = tagged_token("иванову")
      gnc = &Relations.gnc_agrees?/2
      assert Relations.validate_match([{gnc, t1}, {gnc, t2}])
    end

    test "иванов иван agree in number+gender" do
      t1 = tagged_token("иванов")
      t2 = tagged_token("иван")
      ng = fn f1, f2 -> Relations.number_agrees?(f1, f2) and Relations.gender_agrees?(f1, f2) end
      assert Relations.validate_match([{ng, t1}, {ng, t2}])
    end
  end
end
