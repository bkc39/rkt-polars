"""rkt-polars user guide — Expressions: Window functions (Python reference).

Mirrors https://docs.pola.rs/user-guide/expressions/window-functions/
and window-functions.rkt.

Inside `nix develop`:
    python user-guide/expressions/window_functions.py
"""

import polars as pl

# The first rows of upstream's Pokémon table, which it reads from
# docs/assets/data/pokemon.csv and casts to an Enum.
types = (
    "Grass Water Fire Normal Ground Electric Psychic Fighting Bug Steel "
    "Flying Dragon Dark Ghost Poison Rock Ice Fairy".split()
)
type_enum = pl.Enum(types)
pokemon = pl.DataFrame(
    {
        "Name": [
            "Bulbasaur",
            "Ivysaur",
            "Venusaur",
            "Charmander",
            "Charmeleon",
            "Charizard",
            "Mega Charizard X",
            "Squirtle",
            "Wartortle",
            "Blastoise",
        ],
        "Type 1": ["Grass"] * 3 + ["Fire"] * 4 + ["Water"] * 3,
        "Type 2": ["Poison"] * 3 + [None, None, "Flying", "Dragon"] + [None] * 3,
        "Attack": [49, 62, 82, 52, 64, 84, 130, 48, 63, 83],
        "Speed": [45, 60, 80, 65, 80, 100, 100, 43, 58, 78],
    }
).cast({"Type 1": type_enum, "Type 2": type_enum})

print(pokemon)

# --- operations per group ------------------------------------------------
result = pokemon.select(
    pl.col("Name", "Type 1"),
    pl.col("Speed").rank("dense", descending=True).over("Type 1").alias("Speed rank"),
)
print(result)

result = pokemon.select(
    pl.col("Name", "Type 1", "Type 2"),
    pl.col("Speed")
    .rank("dense", descending=True)
    .over("Type 1", "Type 2")
    .alias("Speed rank"),
)
print(result)

# --- mapping results to dataframe rows -----------------------------------
athletes = pl.DataFrame(
    {
        "athlete": list("ABCDEF"),
        "country": ["PT", "NL", "NL", "PT", "PT", "NL"],
        "rank": [6, 1, 5, 4, 2, 3],
    }
)
print(athletes)

result = athletes.select(
    pl.col("athlete", "rank").sort_by(pl.col("rank")).over(pl.col("country")),
    pl.col("country"),
)
print(result)

result = athletes.select(
    pl.all()
    .sort_by(pl.col("rank"))
    .over(pl.col("country"), mapping_strategy="explode"),
)
print(result)

result = athletes.with_columns(
    pl.col("rank").sort().over(pl.col("country"), mapping_strategy="join"),
)
print(result)

# --- windowed aggregation expressions ------------------------------------
result = pokemon.select(
    pl.col("Name", "Type 1", "Speed"),
    pl.col("Speed").mean().over(pl.col("Type 1")).alias("Mean speed in group"),
)
print(result)

# --- more examples -------------------------------------------------------
result = pokemon.sort("Type 1").select(
    pl.col("Type 1").head(3).over("Type 1", mapping_strategy="explode"),
    pl.col("Name")
    .sort_by(pl.col("Speed"), descending=True)
    .head(3)
    .over("Type 1", mapping_strategy="explode")
    .alias("fastest/group"),
    pl.col("Name")
    .sort_by(pl.col("Attack"), descending=True)
    .head(3)
    .over("Type 1", mapping_strategy="explode")
    .alias("strongest/group"),
    pl.col("Name")
    .sort()
    .head(3)
    .over("Type 1", mapping_strategy="explode")
    .alias("sorted_by_alphabet"),
)
print(result)
