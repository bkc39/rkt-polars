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
        "event" => ["open", "lunch", "close"],
        "ts" => [
            ts(2024, 1, 2, 8, 30, 5),
            ts(2024, 1, 2, 12, 15, 0),
            ts(2024, 1, 2, 17, 45, 30),
        ],
    ]?;

    let out = df
        .lazy()
        .with_columns([
            col("ts").dt().year().alias("year"),
            col("ts").dt().month().cast(DataType::Int32).alias("month"),
            col("ts").dt().day().cast(DataType::Int32).alias("day"),
            col("ts").dt().hour().cast(DataType::Int32).alias("hour"),
            col("ts")
                .dt()
                .minute()
                .cast(DataType::Int32)
                .alias("minute"),
            col("ts")
                .dt()
                .second()
                .cast(DataType::Int32)
                .alias("second"),
        ])
        .collect()?;

    println!("datetime expr shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
