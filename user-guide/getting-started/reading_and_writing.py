"""rkt-polars user guide — Getting started: Reading & writing (Python reference).

Mirrors https://docs.pola.rs/user-guide/getting-started/#reading-writing and
reading-and-writing.rkt.

Inside `nix develop`:
    python user-guide/getting-started/reading_and_writing.py
"""

import datetime as dt
import tempfile
from pathlib import Path

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

print(df)

csv_path = Path(tempfile.gettempdir()) / "output.csv"
df.write_csv(csv_path)
df_csv = pl.read_csv(csv_path, try_parse_dates=True)
print(df_csv)
