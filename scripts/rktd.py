"""Python values and polars outcomes as Racket data, for the oracle scripts."""

import datetime as dt
import decimal
import fractions
import json

import polars as pl


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
    pl.UInt64: "uint64", pl.UInt128: "uint128", pl.Float32: "float32", pl.Float64: "float64",
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
