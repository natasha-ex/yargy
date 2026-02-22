# Yargy

Earley parser with grammar DSL for rule-based information extraction from Russian text.

Elixir port of [natasha/yargy](https://github.com/natasha/yargy). Depends on [morph_ru](https://github.com/natasha-ex/morph_ru) for morphological analysis.

- Earley parser optimized for Russian free word order
- **Declarative grammar DSL** with compile-time caching
- 18 predicates: `gram/1`, `type/1`, `eq/1`, `in_/1`, `normalized/1`, `dictionary/1`, …
- Relations for morphological agreement (gender-number-case, number-case)
- Interpretation system for structured output (facts)
- Tokenizer, sentence splitter, morph tagger, morph pipeline
- Built-in grammars: Date, NamedDate, Amount, Person

## Installation

```elixir
def deps do
  [
    {:yargy, "~> 0.2"}
  ]
end
```

## Grammar DSL (v0.2)

Define grammars declaratively with `use Yargy.Grammar`. Rules compile
once at module load time and are cached in `persistent_term`.

```elixir
defmodule MyApp.PersonGrammar do
  use Yargy.Grammar

  defrule :surname, all([gram("Surn"), capitalized()])
  defrule :first_name, all([gram("Name"), capitalized()])
  defrule :patronymic, all([gram("Patr"), capitalized()])
  defrule :dot, token(".")
  defrule :initial, all([upper(), length_eq(1)])
  defrule :initial_dot, rule(:initial) ~> rule(:dot)

  defgrammar :person, choice([
    rule(:surname) ~> rule(:first_name) ~> optional(rule(:patronymic)),
    rule(:first_name) ~> optional(rule(:patronymic)) ~> rule(:surname),
    rule(:surname) ~> rule(:initial_dot) ~> rule(:initial_dot),
    rule(:initial_dot) ~> rule(:initial_dot) ~> rule(:surname)
  ])
end

# Use the generated functions:
MyApp.PersonGrammar.person_text("Адвокат Иванов Иван Петрович подписал")
# [%Yargy.Parser.Match{tokens: [...], start: 1, stop: 4}]
```

### Terminals

| Function | Matches |
|---|---|
| `token("ст")` | exact value |
| `token(~w[ГК ТК НК])` | value in set |
| `lemma("статья")` | any morphological form |
| `lemma(~w[статья закон])` | lemma in set |
| `gram("VERB")` | has OpenCorpora grammeme |
| `integer()` | token type `:int` |
| `word()` | token type `:word` |
| `punct(".")` | punctuation with exact value |
| `capitalized()` | first char uppercase |
| `upper()` | all chars uppercase |
| `caseless("рублей")` | case-insensitive |
| `all([gram("Surn"), capitalized()])` | AND — same token matches all |
| `any([token("ст"), lemma("статья")])` | OR — same token matches any |

### Composition

| Syntax | Meaning |
|---|---|
| `a ~> b` | sequence (a then b) |
| `choice([a, b])` | alternation |
| `optional(a)` | zero or one |
| `repeat(a)` | one or more |
| `repeat(a, min: 2, max: 5)` | bounded repetition |
| `rule(:name)` | reference a defrule |

### Generated functions

`defgrammar :person, ...` generates:

- `person(tokens)` — find all matches in morph-tagged tokens
- `person_text(text)` — tokenize + morph-tag, then find matches
- `person_parser()` — return the pre-built `%Parser{}` struct

## Low-level API

The DSL compiles to the same `Rule` / `Predicate` / `Parser` primitives
you can use directly:

```elixir
alias Yargy.{Parser, Predicate, Rule, Tokenizer}

date = Rule.rule([
  Predicate.type(:int), Predicate.eq("."),
  Predicate.type(:int), Predicate.eq("."),
  Predicate.type(:int)
])

tokens = Tokenizer.tokenize("Договор от 15.03.2024 подписан.")
Parser.findall(Parser.new(date), tokens)
```

### Partial matching (autocomplete)

When the input ends mid-parse, `partial_matches/2` returns incomplete states
from the Earley chart — useful for autocomplete.

```elixir
rule = Rule.rule([
  Predicate.in_(~w(ООО ПАО АО)),
  Predicate.or_([Predicate.eq("«"), Predicate.eq("\"")]),
  Predicate.type(:word),
  Predicate.or_([Predicate.eq("»"), Predicate.eq("\"")])
])

parser = Parser.new(rule)
tokens = Tokenizer.tokenize("Директору ООО «Ромашка")

Parser.partial_matches(parser, tokens)
# [%{dot: 3, production_length: 4, progress: 0.75,
#    matched_text: "ООО « Ромашка", ...}]
```

### Sentence splitting

```elixir
Yargy.Sentenize.sentenize("Привет. Как дела? Хорошо!")
# ["Привет.", "Как дела?", "Хорошо!"]
```

## Core modules

| Module | Purpose |
|---|---|
| `Yargy.Grammar` | Declarative DSL — `defrule`, `defgrammar`, terminals, `~>` |
| `Yargy.Parser` | Earley parser — `findall/2`, `find/2`, `partial_matches/2` |
| `Yargy.Rule` | Low-level rule builder — `rule`, `or_rule`, `optional`, `repeatable` |
| `Yargy.Predicate` | Token predicates — `gram`, `type`, `eq`, `normalized` |
| `Yargy.Relations` | Agreement — `gnc_relation`, `nc_relation` |
| `Yargy.Tokenizer` | UTF-8 tokenizer with byte/char position tracking |
| `Yargy.Sentenize` | Sentence splitter |
| `Yargy.MorphTagger` | Morphological tagging via morph_ru |
| `Yargy.Grammars.*` | Date, NamedDate, Amount, Person |

## License

MIT © Danila Poyarkov
