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

# --- read ------------------------------------------------------------------
print(pl.read_json(stations))

# --- write -----------------------------------------------------------------
path = Path(tempfile.gettempdir()) / "polars-guide-path.json"
df = pl.DataFrame({"foo": [1, 2, 3], "bar": [None, "bak", "baz"]})
df.write_json(path)
print(path.read_text())
print(pl.read_json(path))
path.unlink()

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
