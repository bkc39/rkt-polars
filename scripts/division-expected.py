"""Writes polars/tests/generic/division-expected.rktd from Python polars.

Run from the repo root with Python polars 1.42.1:
    python3 -I scripts/division-expected.py
"""

import pathlib
import sys

import polars as pl

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from rktd import Sym, datum, outcome

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "polars" / "tests" / "generic" / "division-expected.rktd"


DTYPES = [
    ("int64", pl.Int64), ("int32", pl.Int32), ("uint8", pl.UInt8), ("uint64", pl.UInt64),
    ("boolean", pl.Boolean), ("null", pl.Null), ("float64", pl.Float64),
]
LEFT = {"signed": [10, -7, None], "unsigned": [10, 7, None], "boolean": [True, False, None],
        "null": [None, None, None], "float": [10.0, -7.0, None]}
RIGHT = {"signed": [3, -2, 0], "unsigned": [3, 2, 0], "boolean": [True, True, False],
         "null": [None, None, None], "float": [3.0, -2.0, 0.0]}
LITERALS = [3, -3, 2**63, 2**64 - 1, 2.5]


def kind(d):
    if d == pl.Null:
        return "null"
    if d == pl.Boolean:
        return "boolean"
    if d.is_float():
        return "float"
    return "unsigned" if d.is_unsigned_integer() else "signed"


def integer_like(v):
    if isinstance(v, pl.Series):
        return v.dtype.is_integer() or v.dtype in (pl.Boolean, pl.Null)
    return isinstance(v, int) and not isinstance(v, bool)


def divide(a, b, a_integer, b_integer, both_null):
    return a // b if a_integer and b_integer and not both_null else a / b


def column(name, d, values):
    return pl.Series(name, values, dtype=d)


rows = []
for ln, ld in DTYPES:
    a = column("a", ld, LEFT[kind(ld)])
    for rn, rd in DTYPES:
        b = column("b", rd, RIGHT[kind(rd)])
        flags = (integer_like(a), integer_like(b), ld == pl.Null and rd == pl.Null)
        rows.append([Sym("series"), Sym(ln), Sym(rn), outcome(lambda: divide(a, b, *flags))])
    for v in LITERALS:
        for side in ("right", "left"):
            flags = (integer_like(a), integer_like(v), False)
            x, y = (a, v) if side == "right" else (v, a)
            ex, ey = (pl.col("a"), pl.lit(v)) if side == "right" else (pl.lit(v), pl.col("a"))
            frame = pl.DataFrame([a])
            rows.append([Sym("value"), Sym(ln), Sym(side), v,
                         outcome(lambda: divide(x, y, *flags)),
                         outcome(lambda: frame.select(divide(ex, ey, *flags).alias("a"))["a"])])

out = [f"((python-polars {datum(pl.__version__)})", " (rows"]
out.extend(f"  {datum(r)}" for r in rows)
out[-1] += "))"
OUT.write_text("\n".join(out) + "\n")
