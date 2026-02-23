"""Benchmark Python yargy/natasha/razdel for comparison with Elixir port."""

import time
import os
import statistics

from yargy import Parser, rule, or_
from yargy.predicates import (
    eq, in_, in_caseless, type as type_, normalized, gram,
    gte, lte, caseless, is_capitalized, is_upper, length_eq
)
from yargy.tokenizer import MorphTokenizer

from razdel import sentenize as razdel_sentenize

# Load fixtures
fixture_dir = os.path.join(os.path.dirname(__file__), '..', 'test', 'fixtures')
with open(os.path.join(fixture_dir, '001_penalty_late_delivery.txt'), encoding='utf-8') as f:
    fixture1 = f.read()
with open(os.path.join(fixture_dir, '002_defective_claim.txt'), encoding='utf-8') as f:
    fixture2 = f.read()

short_text = "Ответчик Иванов Иван Петрович не исполнил обязательства по договору от 15.03.2024"
medium_text = fixture1
long_text = (fixture1 + "\n\n" + fixture2) * 5

print("=== Python yargy/natasha Benchmark ===\n")
print(f"Text sizes:")
print(f"  short:  {len(short_text)} chars")
print(f"  medium: {len(medium_text)} chars")
print(f"  long:   {len(long_text)} chars")
print()


def measure(label, fn, iterations=50):
    # warmup
    for _ in range(3):
        fn()

    times = []
    for _ in range(iterations):
        start = time.perf_counter()
        fn()
        elapsed = (time.perf_counter() - start) * 1_000_000  # microseconds
        times.append(elapsed)

    avg = statistics.mean(times)
    med = statistics.median(times)
    p95 = sorted(times)[int(iterations * 0.95)]

    def fmt(us):
        if us >= 1000:
            return f"{us/1000:.1f}ms".rjust(10)
        return f"{int(us)}µs".rjust(10)

    print(f"{label:<45} avg={fmt(avg)}  med={fmt(med)}  p95={fmt(p95)}")
    return avg


# === Tokenizer ===
tokenizer = MorphTokenizer()

print("--- Tokenizer (MorphTokenizer, includes morph) ---")
measure("morph_tokenize(short)", lambda: list(tokenizer(short_text)), 200)
measure("morph_tokenize(medium)", lambda: list(tokenizer(medium_text)), 30)
measure("morph_tokenize(long)", lambda: list(tokenizer(long_text)), 5)
print()

# Count tokens for reference
short_tokens = list(tokenizer(short_text))
medium_tokens = list(tokenizer(medium_text))
long_tokens = list(tokenizer(long_text))
print(f"  token counts: short={len(short_tokens)} medium={len(medium_tokens)} long={len(long_tokens)}")
print()

# === Sentenize ===
print("--- Sentenize (razdel) ---")
measure("sentenize(short)", lambda: list(razdel_sentenize(short_text)), 200)
measure("sentenize(medium)", lambda: list(razdel_sentenize(medium_text)), 20)
measure("sentenize(long)", lambda: list(razdel_sentenize(long_text)), 5)
print()

# === Person grammar ===
SURNAME = rule(gram('Surn'), is_capitalized())
FIRST_NAME = rule(gram('Name'), is_capitalized())
PATRONYMIC = rule(gram('Patr'), is_capitalized())
DOT = rule(eq('.'))
INITIAL = rule(is_upper(), length_eq(1))
INITIAL_DOT = rule(INITIAL, DOT)

PERSON = or_(
    rule(SURNAME, FIRST_NAME, PATRONYMIC.optional()),
    rule(FIRST_NAME, PATRONYMIC.optional(), SURNAME),
    rule(SURNAME, INITIAL_DOT, INITIAL_DOT),
    rule(INITIAL_DOT, INITIAL_DOT, SURNAME),
)

person_parser = Parser(PERSON)

print("--- Parser (Person grammar, includes tokenize+morph) ---")
measure("person_parse(short)", lambda: list(person_parser.findall(short_text)), 200)
measure("person_parse(medium)", lambda: list(person_parser.findall(medium_text)), 20)
measure("person_parse(long)", lambda: list(person_parser.findall(long_text)), 5)
print()

# === Date grammar ===
DAY = rule(type_('INT'), lte(31))
DOT_D = rule(eq('.'))
MONTH_NUM = rule(type_('INT'), lte(12))
YEAR = rule(type_('INT'), gte(1900))
YEAR_SUFFIX = rule(in_caseless({'г', 'года', 'г.'})).optional()

MONTH_NAME = rule(in_caseless({
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
}))

DOT_DATE = rule(DAY, DOT_D, MONTH_NUM, DOT_D, YEAR, YEAR_SUFFIX)
WRITTEN_DATE = rule(DAY, MONTH_NAME, YEAR, YEAR_SUFFIX)
DATE = or_(DOT_DATE, WRITTEN_DATE)

date_parser = Parser(DATE)

print("--- Parser (Date grammar, includes tokenize+morph) ---")
measure("date_parse(short)", lambda: list(date_parser.findall(short_text)), 200)
measure("date_parse(medium)", lambda: list(date_parser.findall(medium_text)), 20)
measure("date_parse(long)", lambda: list(date_parser.findall(long_text)), 5)
print()

# === Amount grammar ===
NUMBER = rule(type_('INT'))
CURRENCY = rule(in_caseless({
    'рублей', 'рубля', 'рубль', 'руб',
    'долларов', 'доллара', 'доллар', 'евро'
}))
OPT_DOT = rule(eq('.')).optional()

AMOUNT = rule(NUMBER.repeatable(), CURRENCY, OPT_DOT)
amount_parser = Parser(AMOUNT)

print("--- Parser (Amount grammar, includes tokenize+morph) ---")
measure("amount_parse(short)", lambda: list(amount_parser.findall(short_text)), 200)
measure("amount_parse(medium)", lambda: list(amount_parser.findall(medium_text)), 20)
measure("amount_parse(long)", lambda: list(amount_parser.findall(long_text)), 5)
print()

print("\n=== Done ===")
