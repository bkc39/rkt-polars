use chrono::NaiveDate;
use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let dates = Series::new(
        "d",
        [
            Some(NaiveDate::from_ymd_opt(2024, 1, 2).unwrap()),
            None,
            Some(NaiveDate::from_ymd_opt(1969, 12, 31).unwrap()),
        ],
    );
    let durations = Series::new("dur", [Some(1500i64), None, Some(-250)])
        .cast(&DataType::Duration(TimeUnit::Milliseconds))?;
    let times =
        Series::new("tod", [Some(11_045_123_456_789i64), None, Some(0)])
            .cast(&DataType::Time)?;

    println!(
        "date dtype={:?} row0={:?} row1={:?} row2={:?}",
        dates.dtype(),
        dates.date()?.get(0),
        dates.date()?.get(1),
        dates.date()?.get(2)
    );
    println!(
        "duration dtype={:?} row0={:?} row1={:?} row2={:?}",
        durations.dtype(),
        durations.duration()?.get(0),
        durations.duration()?.get(1),
        durations.duration()?.get(2)
    );
    println!(
        "time dtype={:?} row0={:?} row1={:?} row2={:?}",
        times.dtype(),
        times.time()?.get(0),
        times.time()?.get(1),
        times.time()?.get(2)
    );

    Ok(())
}
