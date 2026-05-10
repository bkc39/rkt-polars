use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "text" => [
            "  alpha  ",
            "--beta--",
            "id=123",
            "report.txt",
            "banana",
        ],
    ]?;

    let out = df
        .lazy()
        .with_columns([
            col("text")
                .str()
                .strip_chars(Expr::default())
                .alias("trimmed"),
            col("text").str().strip_chars(lit("-")).alias("stripped"),
            col("text")
                .str()
                .strip_prefix(lit("id="))
                .alias("no_prefix"),
            col("text")
                .str()
                .strip_suffix(lit(".txt"))
                .alias("no_suffix"),
            col("text")
                .str()
                .replace(lit(r"\d+"), lit("#"), false)
                .alias("replace_digits"),
            col("text")
                .str()
                .replace_all(lit("a"), lit("A"), true)
                .alias("replace_all_a"),
            col("text")
                .str()
                .extract(lit(r"([0-9]+)"), 1)
                .alias("digits"),
        ])
        .collect()?;

    println!("string expr batch 2 shape={:?}", out.shape());
    println!("{out}");
    Ok(())
}
