use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "x" => [1i32, 2, 2, 3, 5, 5, 8],
    ]?;

    let allowed = Series::new("allowed", &[2i32, 3, 8]);

    let out = df
        .lazy()
        .with_columns([
            col("x").is_in(lit(allowed)).alias("in_allowed"),
            col("x")
                .is_between(lit(2), lit(5), ClosedInterval::Both)
                .alias("in_2_5_both"),
            col("x")
                .is_between(lit(2), lit(5), ClosedInterval::Left)
                .alias("in_2_5_left"),
            col("x").is_unique().alias("uniq"),
            col("x").is_duplicated().alias("dup"),
            col("x").is_first_distinct().alias("first"),
            col("x").is_last_distinct().alias("last"),
        ])
        .collect()?;
    println!("predicates shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
