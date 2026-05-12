use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "x" => [-3i32, 0, 4, 12, 7],
    ]?;

    let out = df
        .lazy()
        .with_columns([
            // single when/then/otherwise
            when(col("x").gt(lit(0)))
                .then(lit("pos"))
                .otherwise(lit("non-pos"))
                .alias("sign"),
            // chained when/then ... otherwise
            when(col("x").lt(lit(0)))
                .then(lit("neg"))
                .when(col("x").eq(lit(0)))
                .then(lit("zero"))
                .when(col("x").lt(lit(10)))
                .then(lit("small"))
                .otherwise(lit("big"))
                .alias("bucket"),
        ])
        .collect()?;

    println!("when/then shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
