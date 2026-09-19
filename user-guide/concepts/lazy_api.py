"""rkt-polars user guide — Concepts: Lazy API (Python reference).

Mirrors https://docs.pola.rs/user-guide/concepts/lazy-api/ and lazy-api.rkt.

Inside `nix develop`:
    python user-guide/concepts/lazy_api.py
"""

from pathlib import Path

import polars as pl

iris_csv = Path(__file__).resolve().parent.parent / "data" / "iris.csv"

# --- eager ---------------------------------------------------------------
df = pl.read_csv(iris_csv)
df_small = df.filter(pl.col("sepal_length") > 5)
df_agg = df_small.group_by("species").agg(pl.col("sepal_width").mean())
print(df_agg)

# --- lazy ----------------------------------------------------------------
q = (
    pl.scan_csv(iris_csv)
    .filter(pl.col("sepal_length") > 5)
    .group_by("species")
    .agg(pl.col("sepal_width").mean())
)

df = q.collect()
print(df)

# --- previewing the query plan -------------------------------------------
print(q.explain())

schema = pl.Schema(
    {
        "int_1": pl.Int16,
        "int_2": pl.Int32,
        "float_1": pl.Float64,
        "float_2": pl.Float64,
        "float_3": pl.Float64,
    }
)

print(
    pl.LazyFrame(schema=schema)
    .select((pl.col(pl.Float64) * 1.1).name.suffix("*1.1"))
    .explain()
)
