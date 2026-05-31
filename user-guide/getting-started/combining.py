"""rkt-polars user guide — Combining DataFrames (Python reference).

Mirrors https://docs.pola.rs/user-guide/getting-started/ and the Racket file
combining.rkt in this directory.

Inside `nix develop`:
    python user-guide/getting-started/combining.py
"""

import polars as pl

users = pl.DataFrame(
    {
        "uid": [1, 2, 3, 4],
        "name": ["alice", "bob", "carol", "dan"],
    }
)

orders = pl.DataFrame(
    {
        "uid": [1, 1, 2, 3],
        "amount": [10, 25, 30, 7],
    }
)

print("users:")
print(users)
print()
print("orders:")
print(orders)
print()

# --- join ---------------------------------------------------------------
print("inner join(uid).group_by(name).agg(total, n).sort(total desc):")
print(
    users.lazy()
    .join(orders.lazy(), on="uid", how="inner")
    .group_by("name")
    .agg(
        pl.col("amount").sum().alias("total"),
        pl.col("amount").count().alias("n"),
    )
    .sort("total", descending=True)
    .collect()
)
print()

print("left join (keeps unmatched users):")
print(users.join(orders, on="uid", how="left"))
print()

# --- concat -------------------------------------------------------------
more_users = pl.DataFrame(
    {
        "uid": [5, 6],
        "name": ["erin", "frank"],
    }
)

print("vertical concat (users ++ more-users):")
print(pl.concat([users, more_users]))
