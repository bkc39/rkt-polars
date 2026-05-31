# rkt-polars user guide

A guided tour of the `polars` Racket bindings, modelled section-by-section on
the upstream [Polars getting-started guide](https://docs.pola.rs/user-guide/getting-started/).

Every topic comes as a matched pair of runnable programs: a Racket version
(`*.rkt`, using these bindings) and a Python version (`*.py`, using upstream
`polars`) that produces the equivalent result, so the two read side by side.

## Running

Everything runs inside the dev shell, which provides both Racket and a Python
with `polars`:

```sh
nix develop

# Racket
racket user-guide/getting-started/series-and-dataframes.rkt

# Python
python user-guide/getting-started/series_and_dataframes.py
```

## Contents

`getting-started/`

| Topic | Racket | Python |
| --- | --- | --- |
| Series & DataFrames | `series-and-dataframes.rkt` | `series_and_dataframes.py` |
| Reading & writing | `reading-and-writing.rkt` | `reading_and_writing.py` |
| Expressions | `expressions.rkt` | `expressions.py` |
| Combining DataFrames | `combining.rkt` | `combining.py` |
