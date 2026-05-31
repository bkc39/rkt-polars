"""rkt-polars user guide — Series & DataFrames (Python reference).

Mirrors https://docs.pola.rs/user-guide/getting-started/ and the Racket file
series-and-dataframes.rkt in this directory.

Inside `nix develop`:
    python user-guide/getting-started/series_and_dataframes.py
"""

import datetime

import polars as pl

# --- Series -------------------------------------------------------------
s = pl.Series("a", [1, 2, 3, 4, 5])

print("a series:")
print(s)
print(f"sum={s.sum()}  min={s.min()}  max={s.max()}  mean={s.mean()}")
print()

# --- DataFrames ---------------------------------------------------------
df = pl.DataFrame(
    {
        "date": [
            datetime.datetime(2025, 1, 1),
            datetime.datetime(2025, 1, 2),
            datetime.datetime(2025, 1, 3),
            datetime.datetime(2025, 1, 4),
        ],
        "float": [1.0, 2.0, 3.0, 4.0],
        "string": ["a", "b", "c", "d"],
    }
)

print("a dataframe:")
print(df)
print()

# --- Viewing data -------------------------------------------------------
print(f"shape = {df.shape}")

print("head(3):")
print(df.head(3))
print()

print("tail(2):")
print(df.tail(2))
print()

print("describe:")
print(df.describe())
print()

print("ref df 'float' then element 0:")
print(f'df["float"][0] = {df["float"][0]}')
