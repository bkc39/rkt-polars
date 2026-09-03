"""rkt-polars user guide — Concepts: Data types and structures (Python reference).

Mirrors https://docs.pola.rs/user-guide/concepts/data-types-and-structures/
and data-types-and-structures.rkt.

Inside `nix develop`:
    python user-guide/concepts/data_types_and_structures.py
"""

from datetime import date

import polars as pl

# --- series --------------------------------------------------------------
s = pl.Series("ints", [1, 2, 3, 4, 5])
print(s)

s1 = pl.Series("ints", [1, 2, 3, 4, 5])
s2 = pl.Series("uints", [1, 2, 3, 4, 5], dtype=pl.UInt64)
print(s1.dtype, s2.dtype)

# --- dataframe -----------------------------------------------------------
df = pl.DataFrame(
    {
        "name": ["Alice Archer", "Ben Brown", "Chloe Cooper", "Daniel Donovan"],
        "birthdate": [
            date(1997, 1, 10),
            date(1985, 2, 15),
            date(1983, 3, 22),
            date(1981, 4, 30),
        ],
        "weight": [57.9, 72.5, 53.6, 83.1],
        "height": [1.56, 1.77, 1.65, 1.75],
    }
)

print(df)

# --- inspecting a dataframe ----------------------------------------------
print(df.head(3))

print(df.glimpse(return_type="string"))

print(df.tail(3))

pl.set_random_seed(42)
print(df.sample(2))

print(df.describe())

# --- schema --------------------------------------------------------------
print(df.schema)

df = pl.DataFrame(
    {
        "name": ["Alice", "Ben", "Chloe", "Daniel"],
        "age": [27, 39, 41, 43],
    },
    schema={"name": None, "age": pl.UInt8},
)

print(df)

df = pl.DataFrame(
    {
        "name": ["Alice", "Ben", "Chloe", "Daniel"],
        "age": [27, 39, 41, 43],
    },
    schema_overrides={"age": pl.UInt8},
)

print(df)
