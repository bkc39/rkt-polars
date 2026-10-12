"""rkt-polars user guide — Time series: Filtering (Python reference).

Mirrors https://docs.pola.rs/user-guide/transformations/time-series/filter/
and filtering.rkt.

Inside `nix develop`:
    python user-guide/time-series/filtering.py
"""

from datetime import datetime
from pathlib import Path

import polars as pl

data_dir = Path(__file__).resolve().parent.parent.parent / "polars" / "scribblings" / "data"

stock = pl.read_csv(data_dir / "apple_stock.csv", try_parse_dates=True)
print(stock)

# --- filtering by single dates -------------------------------------------
print(stock.filter(pl.col("Date") == datetime(1995, 10, 16)))

# --- filtering by a date range -------------------------------------------
print(stock.filter(pl.col("Date").is_between(datetime(1995, 7, 1), datetime(1995, 11, 1))))

# --- filtering with negative dates ---------------------------------------
ts = pl.Series(["-1300-05-23", "-1400-03-02"]).str.to_date()
negative_dates = pl.DataFrame({"ts": ts, "values": [3, 4]})
print(negative_dates.filter(pl.col("ts").dt.year() < -1300))
