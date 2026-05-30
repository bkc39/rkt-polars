use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "x" => [Some(1.0f64), None, Some(3.0), None, Some(5.0)],
        "y" => [1.0f64, f64::NAN, 3.0, f64::INFINITY, -1.0],
    ]?;

    let out = df
        .clone()
        .lazy()
        .with_columns([
            col("x").fill_null(lit(0.0)).alias("x_filled"),
            col("x").forward_fill(None).alias("x_ffill"),
            col("x").backward_fill(None).alias("x_bfill"),
            col("x").is_null().alias("x_is_null"),
            col("y").fill_nan(lit(-99.0)).alias("y_no_nan"),
            col("y").is_nan().alias("y_is_nan"),
            col("y").is_finite().alias("y_is_finite"),
            col("y").is_infinite().alias("y_is_inf"),
        ])
        .collect()?;
    println!("null/nan shape={:?}", out.shape());
    println!("{out}");

    // drop_nulls / drop_nans collapse the column length
    let dn = df
        .lazy()
        .select([col("x").drop_nulls().alias("x_no_null")])
        .collect()?;
    println!("after drop_nulls: {dn}");
    Ok(())
}
