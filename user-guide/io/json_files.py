"""rkt-polars user guide — IO: JSON files (Python reference).

Mirrors https://docs.pola.rs/user-guide/io/json/ and json-files.rkt; the reading
options below extend the upstream page.

Inside `nix develop`:
    python user-guide/io/json_files.py
"""

import tempfile
from pathlib import Path

import polars as pl

data_dir = Path(__file__).resolve().parent.parent.parent / "polars" / "scribblings" / "data"
stations = data_dir / "stations.json"
stations_nd = data_dir / "stations.ndjson"

# --- read ------------------------------------------------------------------
print(pl.read_json(stations))
print(pl.read_ndjson(stations_nd))

# --- write -----------------------------------------------------------------
tmp = tempfile.TemporaryDirectory()
out = Path(tmp.name)
path = out / "path.json"
nd_path = out / "path.ndjson"
df = pl.DataFrame({"foo": [1, 2, 3], "bar": [None, "bak", "baz"]})
df.write_json(path)
print(path.read_text())
print(pl.read_json(path))
df.write_ndjson(nd_path)
print(nd_path.read_text())
print(pl.read_ndjson(nd_path))

# --- scan --------------------------------------------------------------------
print(pl.scan_ndjson(stations_nd))
print(pl.scan_ndjson(stations_nd).filter(pl.col("reading") > 3).collect())

# --- reading options ---------------------------------------------------------
print(
    pl.read_json(
        stations,
        schema={"day": pl.Date, "station": pl.Categorical, "reading": pl.Float32},
    )
)
print(pl.read_json(stations, schema_overrides={"day": pl.Date}).select("day", "reading"))

try:
    pl.read_json(stations, infer_schema_length=1)
except pl.exceptions.ComputeError as e:
    print(str(e).splitlines()[0])
print(pl.read_json(stations, infer_schema_length=None).shape)

print(pl.read_ndjson(stations_nd, infer_schema_length=2).columns)
try:
    pl.read_ndjson(stations_nd, infer_schema_length=1)
except pl.exceptions.ComputeError as e:
    print(str(e).splitlines()[0])
print(
    pl.read_ndjson(stations_nd, infer_schema_length=1, ignore_errors=True).select(
        "station", "reading"
    )
)

for i in (1, 2, 3):
    pl.read_csv(data_dir / "parts" / f"part-{i}.csv").write_ndjson(out / f"part-{i}.ndjson")
print(pl.read_ndjson(out / "part-*.ndjson", n_rows=4, row_index_name="row"))
tmp.cleanup()
