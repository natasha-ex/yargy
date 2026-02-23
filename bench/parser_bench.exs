alias Yargy.{Parser, Pipeline, Tokenizer, MorphTagger}

fixture1 = File.read!(Path.join([__DIR__, "..", "test", "fixtures", "001_penalty_late_delivery.txt"]))
fixture2 = File.read!(Path.join([__DIR__, "..", "test", "fixtures", "002_defective_claim.txt"]))
long_text = String.duplicate(fixture1 <> "\n\n" <> fixture2, 5)

short_text = "Ответчик Иванов Иван Петрович не исполнил обязательства по договору от 15.03.2024"
medium_text = fixture1

IO.puts("=== Yargy Parser Benchmark ===\n")
IO.puts("Text sizes:")
IO.puts("  short:  #{String.length(short_text)} chars")
IO.puts("  medium: #{String.length(medium_text)} chars")
IO.puts("  long:   #{String.length(long_text)} chars")
IO.puts("")

defmodule Bench do
  def measure(label, fun, iterations \\ 50) do
    for _ <- 1..3, do: fun.()

    times =
      for _ <- 1..iterations do
        {us, _} = :timer.tc(fun)
        us
      end

    avg = Enum.sum(times) / iterations
    median = Enum.sort(times) |> Enum.at(div(iterations, 2))
    p95 = Enum.sort(times) |> Enum.at(trunc(iterations * 0.95))

    IO.puts(
      String.pad_trailing(label, 45) <>
        "avg=#{pad_us(avg)}  med=#{pad_us(median)}  p95=#{pad_us(p95)}"
    )

    avg
  end

  defp pad_us(us) when us >= 1000, do: String.pad_leading("#{Float.round(us / 1000, 1)}ms", 10)
  defp pad_us(us), do: String.pad_leading("#{round(us)}µs", 10)
end

IO.puts("--- Tokenizer ---")
Bench.measure("tokenize(short)", fn -> Tokenizer.tokenize(short_text) end, 200)
Bench.measure("tokenize(medium)", fn -> Tokenizer.tokenize(medium_text) end, 50)
Bench.measure("tokenize(long)", fn -> Tokenizer.tokenize(long_text) end, 10)
IO.puts("")

IO.puts("--- MorphTagger ---")
short_tokens = Tokenizer.tokenize(short_text)
medium_tokens = Tokenizer.tokenize(medium_text)
long_tokens = Tokenizer.tokenize(long_text)
IO.puts("  token counts: short=#{length(short_tokens)} medium=#{length(medium_tokens)} long=#{length(long_tokens)}")

Bench.measure("morph_tag(short)", fn -> MorphTagger.tag(short_tokens) end, 200)
Bench.measure("morph_tag(medium)", fn -> MorphTagger.tag(medium_tokens) end, 30)
Bench.measure("morph_tag(long)", fn -> MorphTagger.tag(long_tokens) end, 5)
IO.puts("")

IO.puts("--- Pipeline (tokenize + morph) ---")
Bench.measure("morph_tokenize(short)", fn -> Pipeline.morph_tokenize(short_text) end, 200)
Bench.measure("morph_tokenize(medium)", fn -> Pipeline.morph_tokenize(medium_text) end, 30)
Bench.measure("morph_tokenize(long)", fn -> Pipeline.morph_tokenize(long_text) end, 5)
IO.puts("")

IO.puts("--- Sentenize (via razdel) ---")
Bench.measure("sentenize(short)", fn -> Razdel.sentenize(short_text) end, 200)
Bench.measure("sentenize(medium)", fn -> Razdel.sentenize(medium_text) end, 20)
Bench.measure("sentenize(long)", fn -> Razdel.sentenize(long_text) end, 5)
IO.puts("")

IO.puts("--- Parser (Person grammar) ---")
Yargy.Grammars.Person.__yargy_init__()
person_parser = Yargy.Grammars.Person.person_parser()

short_tagged = Pipeline.morph_tokenize(short_text)
medium_tagged = Pipeline.morph_tokenize(medium_text)
long_tagged = Pipeline.morph_tokenize(long_text)

Bench.measure("person_parse(short)", fn -> Parser.findall(person_parser, short_tagged) end, 200)
Bench.measure("person_parse(medium)", fn -> Parser.findall(person_parser, medium_tagged) end, 20)
Bench.measure("person_parse(long)", fn -> Parser.findall(person_parser, long_tagged) end, 5)
IO.puts("")

IO.puts("--- Parser (Date grammar) ---")
Yargy.Grammars.Date.__yargy_init__()
dot_date_parser = Yargy.Grammars.Date.dot_date_parser()
written_date_parser = Yargy.Grammars.Date.written_date_parser()

Bench.measure("dot_date_parse(short)", fn -> Parser.findall(dot_date_parser, short_tagged) end, 200)
Bench.measure("dot_date_parse(medium)", fn -> Parser.findall(dot_date_parser, medium_tagged) end, 20)
Bench.measure("dot_date_parse(long)", fn -> Parser.findall(dot_date_parser, long_tagged) end, 5)
Bench.measure("written_date_parse(medium)", fn -> Parser.findall(written_date_parser, medium_tagged) end, 20)
IO.puts("")

IO.puts("--- Parser (Amount grammar) ---")
Yargy.Grammars.Amount.__yargy_init__()
amount_parser = Yargy.Grammars.Amount.amount_parser()

Bench.measure("amount_parse(short)", fn -> Parser.findall(amount_parser, short_tagged) end, 200)
Bench.measure("amount_parse(medium)", fn -> Parser.findall(amount_parser, medium_tagged) end, 20)
Bench.measure("amount_parse(long)", fn -> Parser.findall(amount_parser, long_tagged) end, 5)
IO.puts("")

IO.puts("--- End-to-end: Person (text → matches) ---")
Bench.measure("person_e2e(short)", fn -> Yargy.Grammars.Person.person_text(short_text) end, 200)
Bench.measure("person_e2e(medium)", fn -> Yargy.Grammars.Person.person_text(medium_text) end, 30)
Bench.measure("person_e2e(long)", fn -> Yargy.Grammars.Person.person_text(long_text) end, 5)
IO.puts("")

IO.puts("--- End-to-end: Date (text → matches) ---")
Bench.measure("date_e2e(short)", fn -> Yargy.Grammars.Date.extract(short_text) end, 200)
Bench.measure("date_e2e(medium)", fn -> Yargy.Grammars.Date.extract(medium_text) end, 30)
Bench.measure("date_e2e(long)", fn -> Yargy.Grammars.Date.extract(long_text) end, 5)
IO.puts("")

IO.puts("--- End-to-end: Amount (text → matches) ---")
Bench.measure("amount_e2e(short)", fn -> Yargy.Grammars.Amount.extract(short_text) end, 200)
Bench.measure("amount_e2e(medium)", fn -> Yargy.Grammars.Amount.extract(medium_text) end, 30)
Bench.measure("amount_e2e(long)", fn -> Yargy.Grammars.Amount.extract(long_text) end, 5)

IO.puts("\n=== Done ===")
