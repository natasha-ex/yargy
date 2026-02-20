defmodule Yargy.Token do
  @moduledoc """
  A token with value, type, position, and morphological forms.

  Types: :word, :int, :punct, :other
  """

  @type token_type :: :word | :int | :punct | :other

  @type form :: %{
          normalized: String.t(),
          grams: MapSet.t(String.t())
        }

  @type t :: %__MODULE__{
          value: String.t(),
          type: token_type(),
          start: non_neg_integer(),
          stop: non_neg_integer(),
          forms: [form()]
        }

  defstruct [:value, :type, :start, :stop, forms: []]

  def new(value, type, start, stop) do
    %__MODULE__{value: value, type: type, start: start, stop: stop}
  end

  def with_forms(%__MODULE__{} = token, forms) do
    %{token | forms: forms}
  end

  def normalized(%__MODULE__{forms: [first | _]}), do: first.normalized
  def normalized(%__MODULE__{value: value}), do: String.downcase(value)
end
