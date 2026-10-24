"""Writes polars/private/generic/operand-audit.rktd from Python polars.

Run from the repo root with Python polars 1.42.1:
    python3 -I scripts/operand-audit-expected.py
then scripts/operand-audit-deviations.rkt to record Racket's outcome on the
rows where it differs (--accept admits new and changed rows; see AGENTS.md).
"""

import datetime as dt
import decimal
import fractions
import json
import pathlib
import warnings
import zoneinfo

import polars as pl

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "polars" / "scribblings" / "data"
OUT = ROOT / "polars" / "private" / "generic" / "operand-audit.rktd"
PARIS = zoneinfo.ZoneInfo("Europe/Paris")
warnings.simplefilter("ignore")


class Sym(str):
    pass


def datum(v):
    if v is None:
        return "null"
    if isinstance(v, Sym):
        return str(v)
    if isinstance(v, bool):
        return "#t" if v else "#f"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, fractions.Fraction):
        return f"{v.numerator}/{v.denominator}" if v.denominator != 1 else str(v.numerator)
    if isinstance(v, float):
        if v != v:
            return "+nan.0"
        if v in (float("inf"), float("-inf")):
            return "+inf.0" if v > 0 else "-inf.0"
        return repr(v)
    if isinstance(v, decimal.Decimal):
        return datum(fractions.Fraction(v))
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (list, tuple)):
        return "(" + " ".join(datum(x) for x in v) + ")"
    if isinstance(v, dt.datetime):
        fields = [v.year, v.month, v.day, v.hour, v.minute, v.second, v.microsecond * 1000]
        if v.tzinfo is None:
            return datum([Sym("datetime"), *fields])
        return datum([Sym("moment"), *fields, v.tzinfo.key])
    if isinstance(v, dt.date):
        return datum([Sym("date"), v.year, v.month, v.day])
    if isinstance(v, dt.time):
        return datum([Sym("time"), v.hour, v.minute, v.second, v.microsecond * 1000])
    if isinstance(v, dt.timedelta):
        return datum([Sym("duration-us"), v // dt.timedelta(microseconds=1)])
    raise TypeError(repr(v))


UNITS = {"ms": "milliseconds", "us": "microseconds", "ns": "nanoseconds"}
DTYPES = {
    pl.Int8: "int8", pl.Int16: "int16", pl.Int32: "int32", pl.Int64: "int64",
    pl.Int128: "int128", pl.UInt8: "uint8", pl.UInt16: "uint16", pl.UInt32: "uint32",
    pl.UInt64: "uint64", pl.Float32: "float32", pl.Float64: "float64",
    pl.String: "string", pl.Boolean: "boolean", pl.Date: "date", pl.Time: "time",
    pl.Categorical: "categorical", pl.Null: "null", pl.Binary: "binary",
}


def dtype_datum(d):
    if isinstance(d, pl.Datetime):
        return [Sym("datetime"), Sym(UNITS[d.time_unit]), d.time_zone or False]
    if isinstance(d, pl.Duration):
        return [Sym("duration"), Sym(UNITS[d.time_unit])]
    if isinstance(d, pl.Decimal):
        return [Sym("decimal"), d.precision, d.scale]
    if isinstance(d, pl.Enum):
        return [Sym("enum"), *map(Sym, d.categories.to_list())]
    return Sym(DTYPES[d.base_type()])


def cell(v, categorical):
    return Sym(v) if categorical and v is not None else v


def outcome(f):
    try:
        s = f()
    except Exception as e:
        return [Sym("raises"), Sym(type(e).__name__)]
    if not isinstance(s, pl.Series):
        return [Sym("value"), s]
    categorical = isinstance(s.dtype, (pl.Categorical, pl.Enum))
    return [Sym("series"), s.name, dtype_datum(s.dtype),
            [cell(v, categorical) for v in s.to_list()]]


prices = pl.read_parquet(DATA / "produce.parquet")["price"].head(2).alias("n")
NUMBER_TEXT = [1e-05, 0.0001, 1e16, 1e22, float("inf"), float("-inf"), float("nan"), -0.0,
               0.1 + 0.2, 123456789.0, 5e-324, 2**63, fractions.Fraction(1, 3)]

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
FIXTURES = SERIES + [
    ("number-text", pl.Series("n", [str(float(v)) if isinstance(v, fractions.Fraction)
                                    else str(v) for v in NUMBER_TEXT])),
]
BY_LABEL = dict(FIXTURES)

PLAIN = [1, -1, 300, 2**40, 2**63, 2**64 - 1, fractions.Fraction(1, 3), 2.5, "x", Sym("x"), True, None,
         dt.date(2024, 1, 1), dt.time(1), dt.timedelta(hours=1), dt.datetime(2024, 1, 1),
         dt.datetime(2024, 1, 1, tzinfo=PARIS)]


def python_value(v):
    if isinstance(v, fractions.Fraction):
        return float(v)
    if isinstance(v, Sym):
        return str(v)
    return v


def integer_like(v):
    if isinstance(v, pl.Series):
        return v.dtype.is_integer() or v.dtype in (pl.Boolean, pl.Null)
    return v is None or isinstance(v, int)


def truediv(a, b):
    return a / b


def floordiv(a, b):
    return a // b


OPS = [
    ("+", lambda a, b: a + b),
    ("-", lambda a, b: a - b),
    ("*", lambda a, b: a * b),
    ("/", truediv),
    ("mod", lambda a, b: a % b),
    ("=", lambda a, b: a == b),
    ("!=", lambda a, b: a != b),
    ("<", lambda a, b: a < b),
    (">", lambda a, b: a > b),
    ("<=", lambda a, b: a <= b),
    (">=", lambda a, b: a >= b),
    ("and", lambda a, b: a & b),
    ("or", lambda a, b: a | b),
    ("xor", lambda a, b: a ^ b),
]


def forms(op, f, s, v, side):
    """The eager outcome first, then each other form that gives another."""
    plain = side != "series"
    other = BY_LABEL[v] if not plain else python_value(v)
    a, b = (other, s) if side == "left" else (s, other)
    found = [("eager", outcome(lambda: f(a, b)))]
    frame = pl.DataFrame([s])
    ea, eb = (pl.lit(other), pl.col("n")) if side == "left" else (pl.col("n"), pl.lit(other))
    candidates = []
    if plain:
        candidates.append(("expression", lambda: frame.select(f(ea, eb).alias("n"))["n"]))
    if op == "/" and integer_like(s) and integer_like(other):
        candidates.append(("floor", lambda: floordiv(a, b)))
        if plain:
            candidates.append(("floor-expression",
                               lambda: frame.select(floordiv(ea, eb).alias("n"))["n"]))
    for name, thunk in candidates:
        got = outcome(thunk)
        if all(got != seen for _, seen in found):
            found.append((name, got))
    return [[Sym(name), got] for name, got in found]


def row(op, label, side, operand, outcomes):
    return datum([Sym(op), Sym(label), Sym(side), operand, *outcomes])


rows = []
for op, f in OPS:
    for label, s in SERIES:
        for other, _ in SERIES:
            rows.append(row(op, label, "series", Sym(other), forms(op, f, s, other, "series")))
        for side in ("right", "left"):
            for v in PLAIN:
                rows.append(row(op, label, side, v, forms(op, f, s, v, side)))
for op, f in OPS[5:8]:
    for side in ("right", "left"):
        for v in NUMBER_TEXT:
            rows.append(row(op, "number-text", side, v,
                            forms(op, f, BY_LABEL["number-text"], v, side)))
for label, s in SERIES:
    rows.append(row("not", label, "unary", Sym("_"), [[Sym("eager"), outcome(lambda: ~s)]]))

out = [f"((python-polars {datum(pl.__version__)})", " (series"]
out.extend(f"  {datum([Sym(label), outcome(lambda: s)])}" for label, s in FIXTURES)
out[-1] += ")"
out.append(" (rows")
out.extend(f"  {r}" for r in rows)
out[-1] += "))"
OUT.write_text("\n".join(out) + "\n")
