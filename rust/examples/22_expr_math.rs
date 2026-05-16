use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "x" => [-2.5f64, -1.0, 0.0, 1.5, 4.0],
    ]?;

    let out = df
        .lazy()
        .with_columns([
            col("x").abs().alias("abs"),
            col("x").sign().alias("sign"),
            col("x").round(1).alias("round1"),
            col("x").floor().alias("floor"),
            col("x").ceil().alias("ceil"),
            col("x").clip(lit(-1.0), lit(2.0)).alias("clip"),
            col("x").clip_min(lit(0.0)).alias("clip_min"),
            col("x").abs().sqrt().alias("sqrt_abs"),
            col("x").exp().alias("exp"),
            col("x").abs().log(2.0).alias("log2_abs"),
            col("x").pow(lit(2)).alias("sq"),
        ])
        .collect()?;
    println!("math shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
