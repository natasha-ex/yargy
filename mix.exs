defmodule Yargy.MixProject do
  use Mix.Project

  @version "0.5.2"

  def project do
    [
      app: :yargy,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
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
      {:razdel, "~> 0.1"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "compile --warnings-as-errors",
        "cmd MIX_ENV=test mix test",
        "credo --strict --min-priority high",
        "dialyzer",
        "ex_dna"
      ]
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
