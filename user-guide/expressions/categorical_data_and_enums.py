"""rkt-polars user guide — Expressions: Categorical data and enums (Python reference).

Mirrors https://docs.pola.rs/user-guide/expressions/categorical-data-and-enums/
and categorical-data-and-enums.rkt.

Inside `nix develop`:
    python user-guide/expressions/categorical_data_and_enums.py
"""

import polars as pl
from polars.exceptions import InvalidOperationError

# --- data type Enum: creating an Enum ------------------------------------
bears_enum = pl.Enum(["Polar", "Panda", "Brown"])
bears = pl.Series(["Polar", "Panda", "Brown", "Brown", "Polar"], dtype=bears_enum)
print(bears)

# --- invalid values ------------------------------------------------------
try:
    bears_kind_of = pl.Series(
        ["Polar", "Panda", "Brown", "Polar", "Shark"],
        dtype=bears_enum,
    )
except InvalidOperationError as exc:
    print("InvalidOperationError:", exc)

# --- category ordering and comparison ------------------------------------
log_levels = pl.Enum(["debug", "info", "warning", "error"])

logs = pl.DataFrame(
    {
        "level": ["debug", "info", "debug", "error"],
        "message": [
            "process id: 525",
            "Service started correctly",
            "startup time: 67ms",
            "Cannot connect to DB!",
        ],
    },
    schema_overrides={
        "level": log_levels,
    },
)

non_debug_logs = logs.filter(
    pl.col("level") > "debug",
)
print(non_debug_logs)

try:
    logs.select(pl.col("level") > "Pretty bad")
except InvalidOperationError as err:
    print(err)

str_series = pl.Series(["info", "debug", "debug", "error"])
print(logs["level"] == str_series)

# --- data type Categorical -----------------------------------------------
bears_cat = pl.Series(
    ["Polar", "Panda", "Brown", "Brown", "Polar"], dtype=pl.Categorical
)
print(bears_cat)

# --- using Categories objects --------------------------------------------
bear_categories = pl.Categories(name="bear_species", physical=pl.UInt8)
bears = pl.DataFrame(
    {"species": ["Polar", "Brown", "Panda", "Brown", "Polar"]},
    schema_overrides={"species": pl.Categorical(bear_categories)},
)
print(bears)

# --- lexical comparison with strings -------------------------------------
print(
    pl.DataFrame({"categorical": bears_cat}).with_columns(
        (pl.col("categorical") < "Cat").alias('categorical < "Cat"')
    )
)

print(
    pl.DataFrame(
        {
            "categorical": bears_cat,
            "string": pl.Series(["Panda", "Brown", "Brown", "Polar", "Polar"]),
        }
    ).with_columns(
        (pl.col("categorical") == pl.col("string")).alias("categorical == string"),
    )
)

# --- combining categorical columns ---------------------------------------
male_bears = pl.DataFrame(
    {
        "species": ["Polar", "Brown", "Panda"],
        "weight": [450, 500, 110],  # kg
    },
    schema_overrides={"species": pl.Categorical},
)
female_bears = pl.DataFrame(
    {
        "species": ["Brown", "Polar", "Panda"],
        "weight": [340, 200, 90],  # kg
    },
    schema_overrides={"species": pl.Categorical},
)
bears = pl.concat([male_bears, female_bears], how="vertical")
print(bears)

# --- categorical encodings -----------------------------------------------
cat_bears = pl.Series(
    ["Polar", "Panda", "Brown", "Brown", "Polar"], dtype=pl.Categorical
)
cat2_series = pl.Series(
    ["Panda", "Brown", "Brown", "Polar", "Polar"], dtype=pl.Categorical
)

print(cat_bears.extend(cat2_series))
