"""rkt-polars user guide — Time series: Parsing (Python reference).

Mirrors https://docs.pola.rs/user-guide/transformations/time-series/parsing/
and parsing.rkt.

Inside `nix develop`:
    python user-guide/time-series/parsing.py
"""

from datetime import date, datetime
from pathlib import Path

import polars as pl

data_dir = Path(__file__).resolve().parent.parent.parent / "polars" / "scribblings" / "data"
apple_stock = data_dir / "apple_stock.csv"

# --- parsing dates from a file: in io/csv.py -------------------------------

# --- casting strings to dates --------------------------------------------
df = pl.read_csv(apple_stock, try_parse_dates=False)
df = df.with_columns(pl.col("Date").str.to_date("%Y-%m-%d"))
print(df)

# --- extracting date features --------------------------------------------
print(df.with_columns(pl.col("Date").dt.year().alias("year")))

# --- dates from Python values (no upstream counterpart) ------------------
closes = pl.Series("Date", [date(1995, 10, 16), date(1995, 11, 1)])
print(closes)
print(closes.to_list())
print(pl.Series("wide", [datetime(1995, 10, 16, 9, 30, 0, 123456), datetime(1600, 1, 1)]))

# --- mixed offsets -------------------------------------------------------
data = [
    "2021-03-27T00:00:00+0100",
    "2021-03-28T00:00:00+0100",
    "2021-03-29T00:00:00+0200",
    "2021-03-30T00:00:00+0200",
]
mixed_parsed = (
    pl.Series(data)
    .str.to_datetime("%Y-%m-%dT%H:%M:%S%z")
    .dt.convert_time_zone("Europe/Brussels")
)
print(mixed_parsed)
