use polars::prelude::*;
use std::fs::File;
use std::io::Write;

fn main() -> PolarsResult<()> {
    let csv_path = std::env::temp_dir().join("rkt-polars-expr-string.csv");
    {
        let mut file = File::create(&csv_path)?;
        writeln!(file, "name,value")?;
        writeln!(file, "Alpha,1")?;
        writeln!(file, "beta,2")?;
        writeln!(file, "Gamma,3")?;
        writeln!(file, "delta,4")?;
    }

    let out = LazyCsvReader::new(&csv_path)
        .finish()?
        .with_columns([
            col("name").str().to_lowercase().alias("lower_name"),
            col("name").str().to_uppercase().alias("upper_name"),
            col("name").str().contains(lit("a"), true).alias("has_a"),
            col("name").str().starts_with(lit("A")).alias("starts_a"),
            col("name").str().ends_with(lit("ta")).alias("ends_ta"),
        ])
        .collect()?;

    println!("string expr shape={:?}", out.shape());
    println!("{out}");

    Ok(())
}
