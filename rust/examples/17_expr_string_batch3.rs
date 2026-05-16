use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "text" => ["hello", "héllo", "banana", "abc123abc"],
    ]?;

    let out = df
        .lazy()
        .with_columns([
            col("text").str().len_bytes().alias("bytes"),
            col("text").str().len_chars().alias("chars"),
            col("text").str().slice(lit(1), lit(3)).alias("slice"),
            col("text").str().head(lit(2)).alias("head"),
            col("text").str().tail(lit(2)).alias("tail"),
            col("text")
                .str()
                .find(lit("[0-9]+"), true)
                .alias("find_digits"),
            col("text").str().find_literal(lit("na")).alias("find_na"),
            col("text")
                .str()
                .count_matches(lit("a"), true)
                .alias("count_a"),
        ])
        .collect()?;

    println!("string expr batch 3 shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
