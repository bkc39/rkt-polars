"""Writes polars/private/generic/operand-audit.rktd from Python polars.

Run from the repo root with Python polars 1.42.1:
    python3 -I scripts/operand-audit-expected.py
"""

import datetime as dt
import decimal
import fractions
import pathlib
import zoneinfo

import polars as pl

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "polars" / "scribblings" / "data"
OUT = ROOT / "polars" / "private" / "generic" / "operand-audit.rktd"
PARIS = zoneinfo.ZoneInfo("Europe/Paris")

prices = pl.read_parquet(DATA / "produce.parquet")["price"].head(2).alias("n")

SERIES = [
    ("int64", pl.Series("n", [1, 2])),
    ("int32", pl.Series("n", [1, 2], dtype=pl.Int32)),
    ("uint8", pl.Series("n", [1, 2], dtype=pl.UInt8)),
    ("uint64", pl.Series("n", [1, 2], dtype=pl.UInt64)),
    ("float32", pl.Series("n", [1.5, 2.0], dtype=pl.Float32)),
    ("float64", pl.Series("n", [1.5, 2.0])),
    ("decimal", prices),
    ("string", pl.Series("n", ["x", "y"])),
    ("boolean", pl.Series("n", [True, False])),
    ("date", pl.Series("n", [dt.date(2024, 1, 1), dt.date(2024, 1, 2)])),
    ("time", pl.Series("n", [dt.time(1), dt.time(2)])),
    ("duration", pl.Series("n", [dt.timedelta(hours=1), dt.timedelta(hours=2)])),
    ("datetime", pl.Series("n", [dt.datetime(2024, 1, 1), dt.datetime(2024, 1, 2)])),
    ("zoned", pl.Series("n", [dt.datetime(2024, 1, 1), dt.datetime(2024, 1, 2)])
     .cast(pl.Datetime("us", "Europe/Paris"))),
    ("categorical", pl.Series("n", ["x", "y"], dtype=pl.Categorical)),
    ("enum", pl.Series("n", ["x", "y"], dtype=pl.Enum(["x", "y"]))),
    ("null", pl.Series("n", [None, None], dtype=pl.Null)),
]

# Each plain operand is the Racket value it stands for, as data, and its
# Python counterpart.  An exact rational stands for its float, and a symbol
# for its name's string, as `lit` reads them.
PLAIN = [
    ("1", 1),
    ("-1", -1),
    ("300", 300),
    ("1099511627776", 2**40),
    ("9223372036854775808", 2**63),
    ("1/3", fractions.Fraction(1, 3)),
    ("2.5", 2.5),
    ('"x"', "x"),
    ("x", "x"),
    ("#t", True),
    ("null", None),
    ("(date 2024 1 1)", dt.date(2024, 1, 1)),
    ("(time 1 0 0 0)", dt.time(1)),
    ("(duration-us 3600000000)", dt.timedelta(hours=1)),
    ("(datetime 2024 1 1 0 0 0 0)", dt.datetime(2024, 1, 1)),
    ('(moment 2024 1 1 0 0 0 0 "Europe/Paris")', dt.datetime(2024, 1, 1, tzinfo=PARIS)),
]

UNITS = {"ms": "milliseconds", "us": "microseconds", "ns": "nanoseconds"}


def python_value(v):
    return float(v) if isinstance(v, fractions.Fraction) else v


def enc_dtype(d):
    if isinstance(d, pl.Datetime):
        zone = "#f" if d.time_zone is None else f'"{d.time_zone}"'
        return f"(datetime {UNITS[d.time_unit]} {zone})"
    if isinstance(d, pl.Duration):
        return f"(duration {UNITS[d.time_unit]})"
    if isinstance(d, pl.Decimal):
        return f"(decimal {d.precision} {d.scale})"
    if isinstance(d, pl.Enum):
        return f"(enum {' '.join(d.categories.to_list())})"
    return {
        pl.Int8: "int8", pl.Int16: "int16", pl.Int32: "int32", pl.Int64: "int64",
        pl.Int128: "int128", pl.UInt8: "uint8", pl.UInt16: "uint16",
        pl.UInt32: "uint32", pl.UInt64: "uint64", pl.Float32: "float32",
        pl.Float64: "float64", pl.String: "string", pl.Boolean: "boolean",
        pl.Date: "date", pl.Time: "time", pl.Categorical: "categorical",
        pl.Null: "null", pl.Binary: "binary",
    }[d.base_type()]


def enc(v, categorical=False):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "#t" if v else "#f"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v != v:
            return "+nan.0"
        if v in (float("inf"), float("-inf")):
            return "+inf.0" if v > 0 else "-inf.0"
        return repr(v)
    if isinstance(v, decimal.Decimal):
        return f'(decimal "{v}")'
    if isinstance(v, str):
        return f'(category "{v}")' if categorical else f'"{v}"'
    if isinstance(v, dt.datetime):
        fields = (f"{v.year} {v.month} {v.day} {v.hour} {v.minute} {v.second} "
                  f"{v.microsecond * 1000}")
        if v.tzinfo is None:
            return f"(datetime {fields})"
        return f'(moment {fields} "{v.tzinfo.key}")'
    if isinstance(v, dt.date):
        return f"(date {v.year} {v.month} {v.day})"
    if isinstance(v, dt.time):
        return f"(time {v.hour} {v.minute} {v.second} {v.microsecond * 1000})"
    if isinstance(v, dt.timedelta):
        return f"(duration-us {v // dt.timedelta(microseconds=1)})"
    raise TypeError(repr(v))


def outcome(f):
    try:
        s = f()
    except Exception as e:
        return type(e).__name__
    if not isinstance(s, pl.Series):
        return f"(not-a-series {type(s).__name__})"
    categorical = isinstance(s.dtype, (pl.Categorical, pl.Enum))
    return f"({enc_dtype(s.dtype)} {' '.join(enc(v, categorical) for v in s.to_list())})"


def integral(v):
    if isinstance(v, pl.Series):
        return v.dtype.is_integer()
    return isinstance(v, int)


def divide(a, b, integers):
    """Our `/` on integer operands is floor division, Python's `//` (#65)."""
    return a // b if integers else a / b


OPS = [
    ("+", lambda a, b, _: a + b),
    ("-", lambda a, b, _: a - b),
    ("*", lambda a, b, _: a * b),
    ("/", divide),
    ("mod", lambda a, b, _: a % b),
    ("=", lambda a, b, _: a == b),
    ("!=", lambda a, b, _: a != b),
    ("<", lambda a, b, _: a < b),
    (">", lambda a, b, _: a > b),
    ("<=", lambda a, b, _: a <= b),
    (">=", lambda a, b, _: a >= b),
    ("and", lambda a, b, _: a & b),
    ("or", lambda a, b, _: a | b),
    ("xor", lambda a, b, _: a ^ b),
]


def eager(f, a, b):
    return outcome(lambda: f(a, b, integral(a) and integral(b)))


def plain(f, s, v, left):
    """The eager outcome, or (either eager expression) when the expression
    form, (op (col name) (lit value)), gives another."""
    v = python_value(v)
    integers = integral(s) and integral(v)
    a, b = (v, s) if left else (s, v)
    eager_outcome = outcome(lambda: f(a, b, integers))
    frame = pl.DataFrame([s])
    a, b = (pl.lit(v), pl.col("n")) if left else (pl.col("n"), pl.lit(v))
    expression = outcome(lambda: frame.select(f(a, b, integers).alias("n"))["n"])
    if expression == eager_outcome:
        return eager_outcome
    return f"(either {eager_outcome} {expression})"


out = [f";; Generated by scripts/operand-audit-expected.py from Python polars {pl.__version__}; "
       "do not edit.",
       ";; Each case is (op series-label series-outcomes right-outcomes left-outcomes):",
       ";; the series against each series, then against each plain operand on its",
       ";; right and on its left, in the order of `series` and `operands`.  An",
       ";; outcome is (dtype value ...) or the class of the exception Python raised;",
       ";; (either eager expression) when the expression form gives another.",
       "((series"]
for label, s in SERIES:
    out.append(f"  ({label} {outcome(lambda: s)})")
out[-1] += ")"
out.append(" (operands")
out.extend(f"  {racket}" for racket, _ in PLAIN)
out[-1] += ")"
out.append(" (cases")
for op, f in OPS:
    for label, s in SERIES:
        against = [eager(f, s, r) for _, r in SERIES]
        right = [plain(f, s, v, False) for _, v in PLAIN]
        left = [plain(f, s, v, True) for _, v in PLAIN]
        out.append(f"  ({op} {label}")
        out.append(f"   ({' '.join(against)})")
        out.append(f"   ({' '.join(right)})")
        out.append(f"   ({' '.join(left)}))")
for label, s in SERIES:
    out.append(f"  (not {label} {outcome(lambda: ~s)})")
out[-1] += "))"
OUT.write_text("\n".join(out) + "\n")
