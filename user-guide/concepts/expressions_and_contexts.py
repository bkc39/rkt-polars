"""rkt-polars user guide — Concepts: Expressions and contexts (Python reference).

Mirrors https://docs.pola.rs/user-guide/concepts/expressions-and-contexts/
and expressions-and-contexts.rkt.

Inside `nix develop`:
    python user-guide/concepts/expressions_and_contexts.py
"""

from datetime import date

import polars as pl

# --- expressions ---------------------------------------------------------
bmi_expr = pl.col("weight") / (pl.col("height") ** 2)
print(bmi_expr)

# --- contexts ------------------------------------------------------------
df = pl.DataFrame(
    {
        "name": ["Alice Archer", "Ben Brown", "Chloe Cooper", "Daniel Donovan"],
        "birthdate": [
            date(1997, 1, 10),
            date(1985, 2, 15),
            date(1983, 3, 22),
            date(1981, 4, 30),
        ],
        "weight": [57.9, 72.5, 53.6, 83.1],  # (kg)
        "height": [1.56, 1.77, 1.65, 1.75],  # (m)
    }
)

print(df)

# select
print(
    df.select(
        bmi=bmi_expr,
        avg_bmi=bmi_expr.mean(),
        ideal_max_bmi=25,
    )
)

print(df.select(deviation=(bmi_expr - bmi_expr.mean()) / bmi_expr.std()))

# with_columns
print(
    df.with_columns(
        bmi=bmi_expr,
        avg_bmi=bmi_expr.mean(),
        ideal_max_bmi=25,
    )
)

# filter
print(
    df.filter(
        pl.col("birthdate").is_between(date(1982, 12, 31), date(1996, 1, 1)),
        pl.col("height") > 1.7,
    )
)

# group_by and aggregations
print(
    df.group_by(
        (pl.col("birthdate").dt.year() // 10 * 10).alias("decade"),
    ).agg(pl.col("name"))
)

print(
    df.group_by(
        (pl.col("birthdate").dt.year() // 10 * 10).alias("decade"),
        (pl.col("height") < 1.7).alias("short?"),
    ).agg(pl.col("name"))
)

print(
    df.group_by(
        (pl.col("birthdate").dt.year() // 10 * 10).alias("decade"),
        (pl.col("height") < 1.7).alias("short?"),
    ).agg(
        pl.len(),
        pl.col("height").max().alias("tallest"),
        pl.col("weight", "height").mean().name.prefix("avg_"),
    )
)

# --- expression expansion ------------------------------------------------
expr = (pl.col(pl.Float64) * 1.1).name.suffix("*1.1")
print(df.select(expr))

df2 = pl.DataFrame(
    {
        "ints": [1, 2, 3, 4],
        "letters": ["A", "B", "C", "D"],
    }
)
print(df2.select(expr))
