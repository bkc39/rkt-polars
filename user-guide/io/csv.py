"""rkt-polars user guide — IO: CSV (Python reference).

Mirrors https://docs.pola.rs/user-guide/io/csv/ and csv.rkt; the reading
options below extend the upstream page.

Inside `nix develop`:
    python user-guide/io/csv.py
"""

import tempfile
from pathlib import Path

import polars as pl

data_dir = Path(__file__).resolve().parent.parent.parent / "polars" / "scribblings" / "data"

# --- read & write ----------------------------------------------------------
path = Path(tempfile.gettempdir()) / "polars-guide-path.csv"
df = pl.DataFrame({"foo": [1, 2, 3], "bar": [None, "bak", "baz"]})
df.write_csv(path)
print(pl.read_csv(path))

# --- scan --------------------------------------------------------------------
print(pl.scan_csv(path).collect())
path.unlink()

# --- reading options ---------------------------------------------------------
flights_tsv = data_dir / "flights.tsv"

# Python returns the header line as one column; read-csv raises instead.
print(pl.read_csv(flights_tsv).shape)

try:
    pl.read_csv(flights_tsv, separator="\t")
except pl.exceptions.ComputeError as e:
    print(str(e).splitlines()[0])
flights = pl.read_csv(flights_tsv, separator="\t", null_values="NA")
print(flights.select("dep_delay", "arr_delay").tail(3))
print(pl.read_csv(flights_tsv, separator="\t", null_values=["NA", "-"])["air_time"].null_count())

print(
    pl.read_csv(
        flights_tsv,
        separator="\t",
        null_values="NA",
        schema_overrides={"dep_delay": pl.Float64, "flight": pl.Int32},
    )
    .select("dep_delay", "flight")
    .tail(2)
)
print(pl.read_csv(flights_tsv, separator="\t", infer_schema_length=None)["dep_delay"].dtype)
print(pl.read_csv(flights_tsv, separator="\t", ignore_errors=True)["dep_delay"].null_count())
print(
    pl.read_csv(flights_tsv, separator="\t", null_values="NA", try_parse_dates=True)
    .select("time_hour")
    .head(2)
)

print(pl.read_csv(data_dir / "notes.csv", separator=";", comment_prefix="#", quote_char="'"))
print(pl.read_csv(data_dir / "latin1.csv", encoding="utf8-lossy"))
print(pl.read_csv(data_dir / "parts" / "part-1.csv", has_header=False, skip_rows=1, n_rows=1))
