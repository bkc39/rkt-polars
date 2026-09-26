"""rkt-polars user guide — IO: Multiple files (Python reference).

Mirrors https://docs.pola.rs/user-guide/io/multiple/ and multiple.rkt.

Inside `nix develop`:
    python user-guide/io/multiple.py
"""

import glob
import shutil
import tempfile
from pathlib import Path

import polars as pl

dir = Path(tempfile.mkdtemp(prefix="polars-guide-"))

# --- create ------------------------------------------------------------------
df = pl.DataFrame({"foo": [1, 2, 3], "bar": [None, "ham", "spam"]})
for i in range(5):
    df.write_csv(dir / f"my_many_files_{i}.csv")

# --- read into a single dataframe ------------------------------------------
print(pl.read_csv(dir / "my_many_files_*.csv"))

for i in range(2):
    df.write_parquet(dir / f"my_many_files_{i}.parquet")
print(pl.read_parquet(dir / "my_many_files_*.parquet").height)

# --- read and process in parallel -------------------------------------------
queries = []
for file in sorted(glob.glob(str(dir / "my_many_files_*.csv"))):
    q = pl.scan_csv(file).group_by("bar").agg(pl.len(), pl.sum("foo")).sort("bar")
    queries.append(q)

for frame in pl.collect_all(queries):
    print(frame)

shutil.rmtree(dir)
