defmodule Yargy.Interpretation.Fact do
  @moduledoc """
  Defines fact schemas for structured information extraction.

  A fact is a named record type with named attributes. When a grammar's
  interpretation extracts data, it populates fact instances.

  ## Usage

      Person = Fact.define("Person", [:first, :last, :patronymic])
      Person.new(first: "Иван", last: "Иванов")
  """

  defstruct [:__schema__, :__attributes__, :__raw__]

  @type t :: %__MODULE__{
          __schema__: atom(),
          __attributes__: map(),
          __raw__: map() | nil
        }

  @doc """
  Defines a new fact schema.

  Returns a module-like map with `new/1`, attribute accessors, and schema metadata.
  """
  def define(name, attributes) when is_binary(name) and is_list(attributes) do
    attr_names = Enum.map(attributes, &normalize_attr/1)

    repeatables =
      attributes |> Enum.filter(&repeatable?/1) |> Enum.map(&attr_name/1) |> MapSet.new()

    schema = String.to_atom(name)

    %{
      __struct__: __MODULE__.Schema,
      name: schema,
      attributes: attr_names,
      repeatables: repeatables,
      defaults:
        Map.new(attr_names, fn a -> {a, if(MapSet.member?(repeatables, a), do: [], else: nil)} end)
    }
  end

  defp normalize_attr(attr) when is_atom(attr), do: attr
  defp normalize_attr(attr) when is_binary(attr), do: String.to_atom(attr)
  defp normalize_attr({:repeatable, attr}), do: normalize_attr(attr)

  defp repeatable?({:repeatable, _}), do: true
  defp repeatable?(_), do: false

  defp attr_name({:repeatable, attr}), do: normalize_attr(attr)
  defp attr_name(attr), do: normalize_attr(attr)

  @doc "Creates a new fact instance from a schema."
  def new(schema, attrs \\ []) do
    attributes = Enum.into(attrs, schema.defaults)

    %__MODULE__{
      __schema__: schema.name,
      __attributes__: attributes,
      __raw__: nil
    }
  end

  @doc "Gets an attribute value."
  def get(%__MODULE__{__attributes__: attrs}, key) when is_atom(key) do
    Map.get(attrs, key)
  end

  @doc "Sets an attribute value (appends for repeatable attributes)."
  def set(%__MODULE__{} = fact, schema, key, value) when is_atom(key) do
    new_attrs =
      if MapSet.member?(schema.repeatables, key) do
        Map.update(fact.__attributes__, key, [value], &(&1 ++ [value]))
      else
        Map.put(fact.__attributes__, key, value)
      end

    %{fact | __attributes__: new_attrs}
  end

  @doc "Merges another fact's modified attributes into this one."
  def merge(%__MODULE__{} = target, %__MODULE__{} = source) do
    merged =
      Enum.reduce(source.__attributes__, target.__attributes__, fn {k, v}, acc ->
        if v != nil, do: Map.put(acc, k, v), else: acc
      end)

    %{target | __attributes__: merged}
  end

  @doc "Converts fact to a plain map (for JSON serialization)."
  def as_json(%__MODULE__{__attributes__: attrs}) do
    attrs
    |> Enum.reject(fn {_k, v} -> v == nil end)
    |> Enum.map(fn {k, v} -> {k, json_value(v)} end)
    |> Map.new()
  end

  defp json_value(%__MODULE__{} = fact), do: as_json(fact)
  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)
  defp json_value(other), do: other

  @doc "Returns the spans from a fact's raw interpretation data."
  def spans(%__MODULE__{__raw__: nil}), do: []
  def spans(%__MODULE__{__raw__: raw}), do: raw_spans(raw)

  defp raw_spans(raw) when is_map(raw) do
    raw
    |> Map.values()
    |> Enum.flat_map(&raw_spans/1)
    |> Enum.sort()
  end

  defp raw_spans(list) when is_list(list), do: Enum.flat_map(list, &raw_spans/1)
  defp raw_spans({start, stop}) when is_integer(start), do: [{start, stop}]
  defp raw_spans(_), do: []
end

defmodule Yargy.Interpretation.Fact.Schema do
  @moduledoc false
  defstruct [:name, :attributes, :repeatables, :defaults]
end
