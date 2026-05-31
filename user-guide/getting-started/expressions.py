"""rkt-polars user guide — Expressions (Python reference).

Mirrors https://docs.pola.rs/user-guide/getting-started/ and the Racket file
expressions.rkt in this directory.

Inside `nix develop`:
    python user-guide/getting-started/expressions.py
"""

import polars as pl

df = pl.DataFrame(
    {
        "group": ["a", "a", "b", "b", "c"],
        "value": [10, 25, 7, 30, 18],
        "cost": [1.2, 2.4, 0.5, 3.1, 1.8],
    }
)

print("input:")
print(df)
print()

# --- select: choose and transform columns ------------------------------
print("select(group, value*cost as spend):")
print(df.select(pl.col("group"), (pl.col("value") * pl.col("cost")).alias("spend")))
print()

# --- with_columns: add derived columns in one pass ---------------------
print("with_columns(double_value, cost_plus_1):")
print(
    df.with_columns(
        (pl.col("value") * 2).alias("double_value"),
        (pl.col("cost") + 1.0).alias("cost_plus_1"),
    )
)
print()

# --- filter: keep rows matching a predicate ----------------------------
print("filter(value > 15 AND cost < 3.0):")
print(df.filter((pl.col("value") > 15) & (pl.col("cost") < 3.0)))
print()

# --- group_by + agg: aggregate per group -------------------------------
print("group_by(group).agg(sum_value, mean_value, n):")
print(
    df.group_by("group").agg(
        pl.col("value").sum().alias("sum_value"),
        pl.col("value").mean().alias("mean_value"),
        pl.col("value").count().alias("n"),
    )
)
