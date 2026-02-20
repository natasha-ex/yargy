# Yargy

Earley parser with grammar DSL for rule-based information extraction from Russian text.

Elixir port of [natasha/yargy](https://github.com/natasha/yargy). Depends on [morph_ru](https://github.com/natasha-ex/morph_ru) for morphological analysis.

- Earley parser optimized for Russian free word order
- Grammar DSL: `rule/1`, `or_rule/1`, `optional/1`, `repeatable/2`, `named/2`
- 18 predicates: `gram/1`, `type/1`, `eq/1`, `in_/1`, `normalized/1`, `dictionary/1`, …
- Relations for morphological agreement (gender-number-case, number-case)
- Interpretation system for structured output (facts)
- Tokenizer, sentence splitter, morph tagger, morph pipeline
- Built-in grammars: Date, NamedDate, Amount, Person

## Installation

```elixir
def deps do
  [
    {:yargy, "~> 0.1"}
  ]
end
```

## Usage

### Built-in Person grammar

```elixir
alias Yargy.{Parser, Tokenizer}
alias Yargy.Grammars.Person

tokens = Tokenizer.tokenize("Адвокат Иван Петров подписал документы.")
matches = Parser.findall(Person.grammar(), tokens)

Enum.map(matches, & &1.fact)
# [%{first_name: "Иван", last_name: "Петров"}]
```

### Custom grammar

```elixir
import Yargy.Rule
import Yargy.Predicate

date = rule([
  type(:int),
  eq("."),
  type(:int),
  eq("."),
  type(:int)
])

tokens = Yargy.Tokenizer.tokenize("Договор от 15.03.2024 подписан.")
matches = Yargy.Parser.findall(date, tokens)
```

### Sentence splitting

```elixir
Yargy.Sentenize.sentenize("Привет. Как дела? Хорошо!")
# ["Привет.", "Как дела?", "Хорошо!"]
```

## Core modules

| Module | Purpose |
|---|---|
| `Yargy.Parser` | Earley parser — `findall/2`, `find/2` |
| `Yargy.Rule` | Grammar DSL — `rule`, `or_rule`, `optional`, `repeatable`, `named` |
| `Yargy.Predicate` | Token predicates — `gram`, `type`, `eq`, `in_`, `normalized`, `dictionary` |
| `Yargy.Relations` | Agreement — `gnc_relation`, `nc_relation`, `number_relation` |
| `Yargy.Tokenizer` | UTF-8 tokenizer with byte/char position tracking |
| `Yargy.Sentenize` | Sentence splitter |
| `Yargy.MorphTagger` | Morphological tagging via morph_ru |
| `Yargy.MorphPipeline` | Phrase matching pipeline |
| `Yargy.Interpretation` | Fact structs from parse results |
| `Yargy.Grammars.*` | Date, NamedDate, Amount, Person |

## License

MIT © Danila Poyarkov
