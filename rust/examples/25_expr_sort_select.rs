use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "x" => [30i64, 10, 50, 20, 40],
        "g" => ["b", "a", "b", "a", "b"],
    ]?;

    // length-preserving ops can live in with_columns
    let ranked = df
        .clone()
        .lazy()
        .with_columns([
            col("x")
                .rank(
                    RankOptions {
                        method: RankMethod::Dense,
                        descending: false,
                    },
                    None,
                )
                .alias("rank_dense"),
            col("x").reverse().alias("x_rev"),
        ])
        .collect()?;
    println!("ranked:\n{ranked}");

    // length-changing ops: each select's columns must share a length
    let sorted = df
        .clone()
        .lazy()
        .select([
            col("x")
                .sort_by(vec![col("x")], SortMultipleOptions::default())
                .alias("x_sorted"),
            col("g")
                .sort_by(vec![col("x")], SortMultipleOptions::default())
                .alias("g_by_x"),
        ])
        .collect()?;
    println!("sorted:\n{sorted}");

    let windowed = df
        .clone()
        .lazy()
        .select([
            col("x").head(Some(2)).alias("x_head2"),
            col("x").tail(Some(2)).alias("x_tail2"),
            col("x").slice(lit(1i64), lit(2i64)).alias("x_slice"),
        ])
        .collect()?;
    println!("windowed:\n{windowed}");

    let filtered = df
        .clone()
        .lazy()
        .select([col("x").filter(col("x").gt(lit(25))).alias("x_big")])
        .collect()?;
    println!("filtered:\n{filtered}");

    let gathered = df
        .lazy()
        .select([col("x")
            .gather(lit(Series::new("idx", &[0i64, 2, 4])))
            .alias("x_gathered")])
        .collect()?;
    println!("gathered:\n{gathered}");
    Ok(())
}
