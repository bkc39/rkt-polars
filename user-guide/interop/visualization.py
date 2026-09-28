"""rkt-polars user guide — Interoperability: Data for a plot (Python reference).

Mirrors the Matplotlib scatter of
https://docs.pola.rs/user-guide/misc/visualization/ and visualization.rkt.
Matplotlib is not in the dev shell, so this builds the points the scatter
takes and prints the first few.

Inside `nix develop`:
    python user-guide/interop/visualization.py
"""

from pathlib import Path

import polars as pl

iris_csv = Path(__file__).resolve().parent.parent / "data" / "iris.csv"

df = pl.read_csv(iris_csv)

sepals = list(zip(df["sepal_width"].to_list(), df["sepal_length"].to_list()))

print(len(sepals))
print(sepals[:3])
