"""rkt-polars user guide — Reading & writing (Python reference).

Mirrors https://docs.pola.rs/user-guide/getting-started/ and the Racket file
reading-and-writing.rkt in this directory.

Inside `nix develop`:
    python user-guide/getting-started/reading_and_writing.py
"""

import datetime
import tempfile
from pathlib import Path

import polars as pl

df = pl.DataFrame(
    {
        "integer": [1, 2, 3],
        "date": [
            datetime.datetime(2025, 1, 1),
            datetime.datetime(2025, 1, 2),
            datetime.datetime(2025, 1, 3),
        ],
        "float": [4.0, 5.0, 6.0],
        "string": ["a", "b", "c"],
    }
)

print("original:")
print(df)
print()

tmp = Path(tempfile.gettempdir())

# --- CSV ----------------------------------------------------------------
csv_path = tmp / "rkt-polars-guide.csv"
df.write_csv(csv_path)
print(f"wrote {csv_path}")
print("read back from CSV:")
print(pl.read_csv(csv_path))
print()

# --- Parquet ------------------------------------------------------------
parquet_path = tmp / "rkt-polars-guide.parquet"
df.write_parquet(parquet_path)
print(f"wrote {parquet_path}")
print("read back from Parquet:")
print(pl.read_parquet(parquet_path))
print()

# --- JSON (newline-delimited) ------------------------------------------
jsonl_path = tmp / "rkt-polars-guide.jsonl"
df.write_ndjson(jsonl_path)
print(f"wrote {jsonl_path}")
print("read back from JSON lines:")
print(pl.read_ndjson(jsonl_path))
