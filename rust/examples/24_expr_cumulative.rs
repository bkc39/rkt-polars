use polars::prelude::*;
use polars::series::ops::NullBehavior;

fn main() -> PolarsResult<()> {
    let df = df![
        "x" => [1i64, 2, 3, 4, 5],
    ]?;

    let out = df
        .lazy()
        .with_columns([
            col("x").cum_sum(false).alias("cumsum"),
            col("x").cum_sum(true).alias("cumsum_rev"),
            col("x").cum_prod(false).alias("cumprod"),
            col("x").cum_min(false).alias("cummin"),
            col("x").cum_max(false).alias("cummax"),
            col("x").cum_count(false).alias("cumcount"),
            col("x").shift(lit(1)).alias("shift1"),
            col("x").shift(lit(-1)).alias("shift_m1"),
            col("x").shift_and_fill(lit(1), lit(0)).alias("shift1_fill0"),
            col("x").diff(1, NullBehavior::Ignore).alias("diff1"),
        ])
        .collect()?;
    println!("cumulative shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
