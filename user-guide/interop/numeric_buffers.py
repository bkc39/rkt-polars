"""rkt-polars user guide — Interoperability: Numeric buffers (Python reference).

Mirrors Series.to_numpy / DataFrame.to_numpy, the NumPy side of
https://docs.pola.rs/user-guide/misc/arrow/, and numeric-buffers.rkt.
to_numpy needs numpy next to polars.

Inside `nix develop`:
    python user-guide/interop/numeric_buffers.py
"""

import polars as pl

df = pl.DataFrame({"foo": [1, 2, 3], "bar": ["ham", "spam", "jam"]})
gappy = pl.Series("value", [1, None, 3])

# --- a series as a NumPy array -------------------------------------------
print(df["foo"].to_numpy().astype(float).tolist())
print(gappy.to_numpy().tolist())
print(gappy.fill_null(-1).cast(pl.Float64).to_numpy().tolist())
if gappy.null_count():
    print(f"value has a null at row {gappy.is_null().arg_true()[0]}")

# --- a dataframe as one array (DataFrame.to_numpy) -----------------------
xy = pl.DataFrame({"a": [1, 2, None], "b": [0.5, 1.5, 2.5]})

m = xy.to_numpy(order="fortran")
print(m.shape, m.ravel(order="F").tolist())
print(xy.to_numpy(order="c").ravel(order="C").tolist())
print(xy.select("b").to_numpy().ravel().tolist())
print(df.to_numpy().dtype)
