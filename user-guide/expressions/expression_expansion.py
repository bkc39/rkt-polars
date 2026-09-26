"""rkt-polars user guide — Expressions: Expression expansion (Python reference).

Mirrors https://docs.pola.rs/user-guide/expressions/expression-expansion/
and expression-expansion.rkt.

Inside `nix develop`:
    python user-guide/expressions/expression_expansion.py
"""

import polars as pl
import polars.selectors as cs
from polars.exceptions import DuplicateError

df = pl.DataFrame(
    {  # As of 14th October 2024, ~3pm UTC
        "ticker": ["AAPL", "NVDA", "MSFT", "GOOG", "AMZN"],
        "company_name": ["Apple", "NVIDIA", "Microsoft", "Alphabet (Google)", "Amazon"],
        "price": [229.9, 138.93, 420.56, 166.41, 188.4],
        "day_high": [231.31, 139.6, 424.04, 167.62, 189.83],
        "day_low": [228.6, 136.3, 417.52, 164.78, 188.44],
        "year_high": [237.23, 140.76, 468.35, 193.31, 201.2],
        "year_low": [164.08, 39.23, 324.39, 121.46, 118.35],
    }
)

print(df)

# --- function col --------------------------------------------------------
eur_usd_rate = 1.09  # As of 14th October 2024

result = df.with_columns(
    (
        pl.col(
            "price",
            "day_high",
            "day_low",
            "year_high",
            "year_low",
        )
        / eur_usd_rate
    ).round(2)
)
print(result)

result = df.with_columns((pl.col(pl.Float64) / eur_usd_rate).round(2))
print(result)

result2 = df.with_columns(
    (
        pl.col(
            pl.Float32,
            pl.Float64,
        )
        / eur_usd_rate
    ).round(2)
)
print(result.equals(result2))

result = df.select(pl.col("ticker", "^.*_high$", "^.*_low$"))
print(result)

try:
    df.select(pl.col("ticker", pl.Float64))
except TypeError as err:
    print("TypeError:", err)

# --- selecting all columns -----------------------------------------------
result = df.select(pl.all())
print(result.equals(df))

# --- excluding columns ---------------------------------------------------
result = df.select(pl.all().exclude("^day_.*$"))
print(result)

result = df.select(pl.col(pl.Float64).exclude("^day_.*$"))
print(result)

# --- column renaming -----------------------------------------------------
gbp_usd_rate = 1.31  # As of 14th October 2024

try:
    df.select(
        pl.col("price") / gbp_usd_rate,  # This would be named "price"...
        pl.col("price") / eur_usd_rate,  # And so would this.
    )
except DuplicateError as err:
    print("DuplicateError:", err)

result = df.select(
    (pl.col("price") / gbp_usd_rate).alias("price (GBP)"),
    (pl.col("price") / eur_usd_rate).alias("price (EUR)"),
)
print(result)

result = df.select(
    (pl.col("^year_.*$") / eur_usd_rate).name.prefix("in_eur_"),
    (pl.col("day_high", "day_low") / gbp_usd_rate).name.suffix("_gbp"),
)
print(result)

result = df.select(pl.all().name.map(str.upper))
print(result)


# --- programmatically generating expressions -----------------------------
def amplitude_expressions(time_periods):
    for tp in time_periods:
        yield (pl.col(f"{tp}_high") - pl.col(f"{tp}_low")).alias(f"{tp}_amplitude")


result = df.with_columns(amplitude_expressions(["day", "year"]))
print(result)

# --- more flexible column selections -------------------------------------
result = df.select(cs.string() | cs.ends_with("_high"))
print(result)

result = df.select(cs.contains("_") - cs.string())
print(result)

people = pl.DataFrame(
    {
        "name": ["Anna", "Bob"],
        "has_partner": [True, False],
        "has_kids": [False, False],
        "has_tattoos": [True, False],
        "is_alive": [True, True],
    }
)

result = people.select((~cs.starts_with("has_").as_expr()).name.prefix("not_"))
print(result)

print(cs.is_selector(~cs.starts_with("has_").as_expr()))
print(
    cs.expand_selector(
        people,
        cs.starts_with("has_"),
    )
)
print(
    [
        (e.meta.output_name(), e.meta.root_names())
        for e in amplitude_expressions(["day", "year"])
    ]
)
