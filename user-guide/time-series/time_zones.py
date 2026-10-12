"""rkt-polars user guide — Time series: Time zones (Python reference).

Mirrors https://docs.pola.rs/user-guide/transformations/time-series/timezones/
and time-zones.rkt.

Inside `nix develop`:
    python user-guide/time-series/time_zones.py
"""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import polars as pl

# --- converting and replacing time zones ---------------------------------
ts = ["2021-03-27 03:00", "2021-03-28 03:00"]
tz_naive = pl.Series("tz_naive", ts).str.to_datetime()
tz_aware = tz_naive.dt.replace_time_zone("UTC").rename("tz_aware")
time_zones_df = pl.DataFrame([tz_naive, tz_aware])
print(time_zones_df)

time_zones_operations = time_zones_df.select(
    [
        pl.col("tz_aware")
        .dt.replace_time_zone("Europe/Brussels")
        .alias("replace time zone"),
        pl.col("tz_aware")
        .dt.convert_time_zone("Asia/Kathmandu")
        .alias("convert time zone"),
        pl.col("tz_aware").dt.replace_time_zone(None).alias("unset time zone"),
    ]
)
print(time_zones_operations)

# --- zoned values from Python (no upstream counterpart) ------------------
landings = pl.Series(
    "landed",
    [
        datetime(2021, 3, 27, 9, tzinfo=ZoneInfo("Europe/Brussels")),
        datetime(2021, 3, 28, 9, tzinfo=ZoneInfo("Europe/Brussels")),
        datetime(2021, 3, 27, 18, tzinfo=ZoneInfo("Asia/Kathmandu")),
    ],
)
print(landings)
print(landings.to_list())
print(pl.Series([datetime(2021, 3, 27, 9, tzinfo=timezone(timedelta(hours=1)))]).dtype)
