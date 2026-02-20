defmodule Yargy.Interpretation.Spec do
  @moduledoc """
  Interpretation specifications attached to rules and predicates.

  A spec describes how to transform matched tokens into structured data.
  Specs are composable: `normalized()`, `inflected(grams)`, `const(value)`,
  `custom(fun)`, `F.attr`, `F.attr.normalized()`, etc.
  """

  defstruct [:type, :schema, :attr, :grams, :value, :fun, :funs]

  @type t :: %__MODULE__{}

  @doc "Attribute assignment: `F.attr`"
  def attribute(schema, attr) when is_atom(attr) do
    %__MODULE__{type: :attribute, schema: schema, attr: attr}
  end

  @doc "Fact construction: `F`"
  def fact(schema) do
    %__MODULE__{type: :fact, schema: schema}
  end

  @doc "Normalized form: `normalized()`"
  def normalized do
    %__MODULE__{type: :normalized}
  end

  @doc "Inflected form: `inflected(grams)`"
  def inflected(grams) when is_list(grams) do
    inflected(MapSet.new(grams))
  end

  def inflected(%MapSet{} = grams) do
    %__MODULE__{type: :inflected, grams: grams}
  end

  @doc "Constant value: `const(value)`"
  def const(value) do
    %__MODULE__{type: :const, value: value}
  end

  @doc "Custom function: `custom(fun)`"
  def custom(fun) when is_function(fun) do
    %__MODULE__{type: :custom, fun: fun}
  end

  @doc "Chained custom functions: `custom(f1).custom(f2)`"
  def custom_chain(funs) when is_list(funs) do
    %__MODULE__{type: :custom_chain, funs: funs}
  end

  @doc "Attribute + normalized: `F.attr.normalized()`"
  def attr_normalized(schema, attr) do
    %__MODULE__{type: :attr_normalized, schema: schema, attr: attr}
  end

  @doc "Attribute + inflected: `F.attr.inflected(grams)`"
  def attr_inflected(schema, attr, grams) do
    %__MODULE__{type: :attr_inflected, schema: schema, attr: attr, grams: normalize_grams(grams)}
  end

  @doc "Attribute + const: `F.attr.const(value)`"
  def attr_const(schema, attr, value) do
    %__MODULE__{type: :attr_const, schema: schema, attr: attr, value: value}
  end

  @doc "Attribute + custom: `F.attr.custom(fun)`"
  def attr_custom(schema, attr, fun) do
    %__MODULE__{type: :attr_custom, schema: schema, attr: attr, fun: fun}
  end

  @doc "Attribute + normalized + custom: `F.attr.normalized().custom(fun)`"
  def attr_normalized_custom(schema, attr, fun) do
    %__MODULE__{type: :attr_normalized_custom, schema: schema, attr: attr, fun: fun}
  end

  @doc "Attribute + inflected + custom: `F.attr.inflected(grams).custom(fun)`"
  def attr_inflected_custom(schema, attr, grams, fun) do
    %__MODULE__{
      type: :attr_inflected_custom,
      schema: schema,
      attr: attr,
      grams: normalize_grams(grams),
      fun: fun
    }
  end

  @doc "Normalized + custom: `normalized().custom(fun)`"
  def normalized_custom(fun) do
    %__MODULE__{type: :normalized_custom, fun: fun}
  end

  @doc "Inflected + custom: `inflected(grams).custom(fun)`"
  def inflected_custom(grams, fun) do
    %__MODULE__{type: :inflected_custom, grams: normalize_grams(grams), fun: fun}
  end

  defp normalize_grams(%MapSet{} = g), do: g
  defp normalize_grams(g) when is_list(g), do: MapSet.new(g)
end
