"""rkt-polars user guide — IO: Parquet (Python reference).

Mirrors https://docs.pola.rs/user-guide/io/parquet/ and parquet.rkt; the
dtypes, pushdown and options sections extend the upstream page.

Inside `nix develop`:
    python user-guide/io/parquet.py
"""

import shutil
import tempfile
from pathlib import Path

import polars as pl

data_dir = Path(__file__).resolve().parent.parent.parent / "polars" / "scribblings" / "data"
tmp = Path(tempfile.mkdtemp(prefix="polars-guide-"))

# --- read --------------------------------------------------------------------
flights = pl.read_parquet(data_dir / "flights.parquet")
print(flights.shape)
print(flights.select("carrier", "dep_delay", "time_hour").head(3))

# --- write -------------------------------------------------------------------
path = tmp / "path.parquet"
df = pl.DataFrame({"foo": [1, 2, 3], "bar": [None, "bak", "baz"]})
df.write_parquet(path)
print(pl.read_parquet(path))

# --- scan --------------------------------------------------------------------
print(pl.scan_parquet(path).collect())

# --- dtypes ------------------------------------------------------------------
produce = pl.read_parquet(data_dir / "produce.parquet")
print(produce)
produce.write_csv(tmp / "produce.csv")
print(pl.read_csv(tmp / "produce.csv"))
produce.write_parquet(tmp / "produce.parquet")
print(pl.read_parquet(tmp / "produce.parquet"))

stamps = flights.select("time_hour")
stamps.write_csv(tmp / "stamps.csv")
print(pl.read_csv(tmp / "stamps.csv")["time_hour"].dtype)
stamps.write_parquet(tmp / "stamps.parquet")
print(pl.read_parquet(tmp / "stamps.parquet")["time_hour"].dtype)

# --- projection and predicate pushdown ---------------------------------------
late = (
    pl.scan_parquet(data_dir / "flights.parquet")
    .filter(pl.col("dep_delay") > 20)
    .select("carrier", "dep_delay")
)
print(late.explain(optimized=False))
print(late.explain())
print(late.collect())

# --- options -----------------------------------------------------------------
print(
    pl.read_parquet(
        data_dir / "flights.parquet",
        columns=["row", "carrier", "dep_delay"],
        n_rows=3,
        row_index_name="row",
    )
)
flights.write_parquet(
    tmp / "flights.parquet",
    compression="gzip",
    compression_level=9,
    statistics="full",
    row_group_size=50,
)
print(pl.read_parquet(tmp / "flights.parquet").shape)

shutil.rmtree(tmp)
