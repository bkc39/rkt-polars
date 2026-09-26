"""The Python polars side of bench/perf.rkt (#86).

Times each operation as the median of 5 runs after a warm-up and prints one
`op<TAB>ms` line per operation, or `op<TAB>n/a<TAB>reason`. The argument names
the inputs perf.rkt used: `original` (the fetched file, `NA` for missing) or
`nona` (the NA-stripped copies).

    python bench/perf.py original
"""

import gc
import statistics
import sys
import time
from pathlib import Path

import polars as pl

DATA = Path(__file__).resolve().parent / "data"

NUMERIC = [
    "year", "month", "day", "dep_time", "sched_dep_time", "dep_delay", "arr_time",
    "sched_arr_time", "arr_delay", "flight", "air_time", "distance", "hour", "minute",
]


def median_ms(fn, runs=5):
    fn()
    times = []
    for _ in range(runs):
        gc.collect()
        start = time.perf_counter()
        result = fn()
        times.append((time.perf_counter() - start) * 1000)
        del result
    return statistics.median(times)


def operations(source):
    stem = "nycflights" if source == "original" else "nycflights-nona"
    tsv, csv = DATA / f"{stem}.tsv", DATA / f"{stem}.csv"
    na = {"null_values": "NA"} if source == "original" else {}
    df = pl.read_csv(tsv, separator="\t", **na) if source == "original" else pl.read_csv(csv)
    return {
        "load-tsv": lambda: pl.read_csv(tsv, separator="\t", **na),
        "load-csv": lambda: pl.read_csv(csv, **na),
        "scan-collect": lambda: pl.scan_csv(tsv, separator="\t", **na).collect(),
        "select": lambda: df.select("distance", "dep_delay", "dest"),
        "distinct": lambda: df.select("dest").unique(),
        "group-by": lambda: df.group_by("dest").agg(
            pl.col("dest").count().alias("n"), pl.col("dep_delay").mean().alias("mean_delay")
        ),
        "filter": lambda: df.filter(pl.col("dep_delay") > 60),
        "sort-top5": lambda: df.sort("dep_delay", descending=True, nulls_last=True).head(5),
        "describe": lambda: df.describe(),
        "column-list": lambda: df["dep_delay"].to_list(),
        "f64-matrix": lambda: df.select(NUMERIC).to_numpy(),
    }


def main(source):
    print(f"version\t{pl.__version__}")
    for key, fn in operations(source).items():
        try:
            print(f"{key}\t{median_ms(fn):.3f}")
        except Exception as e:
            print(f"{key}\tn/a\t{(str(e).splitlines() or [type(e).__name__])[0]}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "original")
