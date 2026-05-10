use polars::prelude::*;
use std::fs::File;
use std::io::Write;

fn main() -> PolarsResult<()> {
    let csv_path = std::env::temp_dir().join("rkt-polars-lazy-io.csv");
    {
        let mut file = File::create(&csv_path)?;
        writeln!(file, "group,value")?;
        writeln!(file, "a,10")?;
        writeln!(file, "a,25")?;
        writeln!(file, "b,7")?;
        writeln!(file, "b,30")?;
    }

    let csv_out = LazyCsvReader::new(&csv_path)
        .finish()?
        .filter(col("value").gt(lit(10)))
        .group_by([col("group")])
        .agg([col("value").sum().alias("total")])
        .sort(["group"], Default::default())
        .collect()?;

    let mut source = df![
        "x" => [1i32, 2, 3, 4],
        "y" => [0.5f64, 1.5, 2.5, 3.5]
    ]?;
    let parquet_path = std::env::temp_dir().join("rkt-polars-lazy-io.parquet");
    {
        let mut file = File::create(&parquet_path)?;
        ParquetWriter::new(&mut file).finish(&mut source)?;
    }

    let parquet_out =
        LazyFrame::scan_parquet(&parquet_path, Default::default())?
            .filter(col("x").gt_eq(lit(2)))
            .select([col("x"), (col("x") * lit(10)).alias("ten_x")])
            .collect()?;

    println!("csv scan shape={:?}", csv_out.shape());
    println!("parquet scan shape={:?}", parquet_out.shape());

    Ok(())
}
