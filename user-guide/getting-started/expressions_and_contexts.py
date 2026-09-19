"""rkt-polars user guide — Getting started: Expressions and contexts (Python reference).

Mirrors https://docs.pola.rs/user-guide/getting-started/#expressions-and-contexts
and expressions-and-contexts.rkt.

Inside `nix develop`:
    python user-guide/getting-started/expressions_and_contexts.py
"""

import datetime as dt

import polars as pl

df = pl.DataFrame(
    {
        "name": ["Alice Archer", "Ben Brown", "Chloe Cooper", "Daniel Donovan"],
        "birthdate": [
            dt.date(1997, 1, 10),
            dt.date(1985, 2, 15),
            dt.date(1983, 3, 22),
            dt.date(1981, 4, 30),
        ],
        "weight": [57.9, 72.5, 53.6, 83.1],
        "height": [1.56, 1.77, 1.65, 1.75],
    }
)

# --- select --------------------------------------------------------------
print(
    df.select(
        pl.col("name"),
        pl.col("birthdate").dt.year().alias("birth_year"),
        (pl.col("weight") / (pl.col("height") ** 2)).alias("bmi"),
    )
)

print(
    df.select(
        pl.col("name"),
        (pl.col("weight", "height") * 0.95).round(2).name.suffix("-5%"),
    )
)

# --- with_columns --------------------------------------------------------
print(
    df.with_columns(
        birth_year=pl.col("birthdate").dt.year(),
        bmi=pl.col("weight") / (pl.col("height") ** 2),
    )
)

# --- filter --------------------------------------------------------------
print(df.filter(pl.col("birthdate").dt.year() < 1990))

print(
    df.filter(
        pl.col("birthdate").is_between(dt.date(1982, 12, 31), dt.date(1996, 1, 1)),
        pl.col("height") > 1.7,
    )
)

# --- group_by ------------------------------------------------------------
print(
    df.group_by(
        (pl.col("birthdate").dt.year() // 10 * 10).alias("decade"),
        maintain_order=True,
    ).len()
)

print(
    df.group_by(
        (pl.col("birthdate").dt.year() // 10 * 10).alias("decade"),
        maintain_order=True,
    ).agg(
        pl.len().alias("sample_size"),
        pl.col("weight").mean().round(2).alias("avg_weight"),
        pl.col("height").max().alias("tallest"),
    )
)

# --- more complex queries ------------------------------------------------
print(
    df.with_columns(
        (pl.col("birthdate").dt.year() // 10 * 10).alias("decade"),
        pl.col("name").str.split(by=" ").list.first(),
    )
    .select(
        pl.all().exclude("birthdate"),
    )
    .group_by(
        pl.col("decade"),
        maintain_order=True,
    )
    .agg(
        pl.col("name"),
        pl.col("weight", "height").mean().round(2).name.prefix("avg_"),
    )
)
