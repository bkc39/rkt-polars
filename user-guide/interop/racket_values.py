"""rkt-polars user guide — Interoperability: Series to Python values (Python reference).

Mirrors https://docs.pola.rs/user-guide/misc/arrow/ (handing a frame's data to
another library), through Series.to_list, DataFrame.iter_columns and
DataFrame.to_dict, and racket-values.rkt.

Inside `nix develop`:
    python user-guide/interop/racket_values.py
"""

import datetime as dt

import polars as pl

df = pl.DataFrame({"foo": [1, 2, 3], "bar": ["ham", "spam", "jam"]})

# --- series to Python values ---------------------------------------------
print(df["foo"].to_list())
print(tuple(df["bar"].to_list()))

gappy = pl.Series("value", [1, None, 3])
print(gappy.to_list())
print(gappy.fill_null(0).to_list())

# every dtype family comes out as a Python value
people = pl.DataFrame(
    {
        "name": ["Alice Archer", "Ben Brown"],
        "birthdate": [dt.datetime(1997, 1, 10, 8, 30), dt.datetime(1985, 2, 15, 17, 0)],
        "weight": [57.9, 72.5],
        "parent": [True, False],
    }
).with_columns(
    pl.col("birthdate").cast(pl.Date).alias("birthday"),
    pl.col("birthdate").cast(pl.Time).alias("clock"),
)
for name in people.columns:
    print(f"{name}: {people[name].to_list()}")

# --- iterating -----------------------------------------------------------
print([word.upper() for word in df["bar"]])
print(sum(gappy.fill_null(0)))
print(next(v for v in pl.Series(range(1_000_000)) if v > 41))
for column in df.iter_columns():
    print(column.name, column.dtype)

# --- columns as Python data ----------------------------------------------
print(df.to_dict(as_series=False))
print(df.to_dict(as_series=False)["bar"])
print(list(df.to_dict(as_series=False).items()))
print(people.select("weight", "name").to_dict(as_series=False))
