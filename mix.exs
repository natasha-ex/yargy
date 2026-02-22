defmodule Yargy.MixProject do
  use Mix.Project

  @version "0.4.1"

  def project do
    [
      app: :yargy,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Earley parser with grammar DSL for Russian NLP",
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:morph_ru, "~> 0.1"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Danila Poyarkov"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/natasha-ex/yargy"},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end
end
