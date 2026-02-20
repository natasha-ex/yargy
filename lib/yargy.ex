defmodule Yargy do
  @moduledoc """
  Earley parser with grammar DSL for Russian NLP.

  Elixir port of [natasha/yargy](https://github.com/natasha/yargy).

  ## Quick start

      import Yargy.{Predicate, Rule}

      # Define a grammar
      name = rule([
        gram("Name"),
        gram("Surn")
      ])

      # Parse text
      Yargy.Parser.findall(name, Yargy.Tokenizer.tokenize("Привет Иван Петров"))
  """
end
