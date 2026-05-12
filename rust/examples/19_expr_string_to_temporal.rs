use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "date_s" => ["2024-01-02", "not-a-date", "2024-05-09 extra"],
        "dt_s" => ["2024-01-02 03:04:05", "bad", "2024-05-09 12:30:45"],
        "time_s" => ["03:04:05.123456789", "bad", "12:30:45"],
    ]?;

    let loose = StrptimeOptions {
        strict: false,
        ..Default::default()
    };
    let embedded_date = StrptimeOptions {
        format: Some("%Y-%m-%d".to_string()),
        strict: false,
        exact: false,
        cache: true,
    };
    let datetime = StrptimeOptions {
        format: Some("%Y-%m-%d %H:%M:%S".to_string()),
        strict: false,
        ..Default::default()
    };
    let time = StrptimeOptions {
        format: Some("%H:%M:%S%.f".to_string()),
        strict: false,
        ..Default::default()
    };

    let out = df
        .lazy()
        .with_columns([
            col("date_s")
                .str()
                .to_date(loose.clone())
                .alias("date_infer"),
            col("date_s")
                .str()
                .to_date(embedded_date)
                .alias("date_embedded"),
            col("dt_s")
                .str()
                .to_datetime(
                    Some(TimeUnit::Milliseconds),
                    None,
                    datetime,
                    lit("raise"),
                )
                .alias("parsed_dt"),
            col("time_s").str().to_time(time).alias("parsed_time"),
        ])
        .collect()?;

    println!("string to temporal shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
