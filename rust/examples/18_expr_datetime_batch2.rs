use chrono::NaiveDate;
use polars::prelude::*;

fn ts(
    year: i32,
    month: u32,
    day: u32,
    hour: u32,
    minute: u32,
    second: u32,
) -> chrono::NaiveDateTime {
    NaiveDate::from_ymd_opt(year, month, day)
        .unwrap()
        .and_hms_opt(hour, minute, second)
        .unwrap()
}

fn main() -> PolarsResult<()> {
    let df = df![
        "ts" => [
            ts(2024, 1, 2, 3, 4, 5),
            ts(2025, 12, 31, 23, 59, 58),
            ts(2026, 5, 9, 12, 30, 45),
        ],
        "t" => [1_704_164_645_123i64, 1_704_164_645_999, 1_704_164_646_000],
    ]?;

    let out = df
        .lazy()
        .with_columns([col("t")
            .cast(DataType::Datetime(TimeUnit::Milliseconds, None))
            .alias("ts_ms")])
        .with_columns([
            col("ts").dt().iso_year().alias("iso_year"),
            col("ts")
                .dt()
                .quarter()
                .cast(DataType::Int32)
                .alias("quarter"),
            col("ts").dt().week().cast(DataType::Int32).alias("week"),
            col("ts")
                .dt()
                .weekday()
                .cast(DataType::Int32)
                .alias("weekday"),
            col("ts")
                .dt()
                .ordinal_day()
                .cast(DataType::Int32)
                .alias("ordinal"),
            col("ts").dt().is_leap_year().alias("leap"),
            col("ts").dt().date().alias("date"),
            col("ts").dt().time().alias("time"),
            col("ts").dt().strftime("%Y-%m-%d").alias("fmt"),
            col("ts_ms").dt().millisecond().alias("ms"),
            col("ts_ms").dt().microsecond().alias("us"),
            col("ts_ms").dt().nanosecond().alias("ns"),
            col("ts_ms")
                .dt()
                .timestamp(TimeUnit::Milliseconds)
                .alias("epoch_ms"),
            col("ts_ms").dt().truncate(lit("1h")).alias("hour_bucket"),
        ])
        .collect()?;

    println!("datetime expr batch 2 shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
