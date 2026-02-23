defmodule Yargy.Sentenize do
  @moduledoc """
  Sentence segmentation for Russian text.

  Delegates to [razdel](https://hex.pm/packages/razdel).
  """

  defdelegate sentenize(text), to: Razdel

  @doc "Splits text into sentence strings."
  def sentences(text) when is_binary(text) do
    text
    |> sentenize()
    |> Enum.map(& &1.text)
  end
end
