# rkt-polars user guide

Runnable companions to the Scribble user guide, modelled chapter by chapter on
the upstream [Polars user guide](https://docs.pola.rs/user-guide/).

Every topic comes as a matched pair of runnable programs: a Racket version
(`*.rkt`, using these bindings) and a Python version (`*.py`, using upstream
`polars`) that produces the equivalent result, so the two read side by side.
Where the bindings have no spelling for an upstream call, the Racket file says
so in an `API gap` comment and shows the nearest workaround.

## Running

Everything runs inside the dev shell, which provides both Racket and a Python
with `polars`:

```sh
nix develop

# Racket
racket user-guide/getting-started/expressions-and-contexts.rkt

# Python
python user-guide/getting-started/expressions_and_contexts.py
```

`raco test user-guide` runs every Racket script; CI does the same.

## Contents

`getting-started/` — [upstream](https://docs.pola.rs/user-guide/getting-started/)

| Topic | Racket | Python |
| --- | --- | --- |
| Reading & writing | `reading-and-writing.rkt` | `reading_and_writing.py` |
| Expressions and contexts | `expressions-and-contexts.rkt` | `expressions_and_contexts.py` |
| Combining dataframes | `combining.rkt` | `combining.py` |

`concepts/` — [upstream](https://docs.pola.rs/user-guide/concepts/)

| Topic | Racket | Python |
| --- | --- | --- |
| Data types and structures | `data-types-and-structures.rkt` | `data_types_and_structures.py` |
| Expressions and contexts | `expressions-and-contexts.rkt` | `expressions_and_contexts.py` |
| Lazy API | `lazy-api.rkt` | `lazy_api.py` |

`data/` holds the small CSV inputs the scripts read.
