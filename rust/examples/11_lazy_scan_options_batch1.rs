use polars::prelude::*;
use std::fs::File;
use std::io::Write;

fn main() -> PolarsResult<()> {
    let csv_path =
        std::env::temp_dir().join("rkt-polars-lazy-scan-options.csv");
    {
        let mut file = File::create(&csv_path)?;
        writeln!(file, "ignore;999")?;
        writeln!(file, "group;value")?;
        writeln!(file, "a;10")?;
        writeln!(file, "a;25")?;
        writeln!(file, "b;7")?;
        writeln!(file, "b;30")?;
    }

    let csv_out = LazyCsvReader::new(&csv_path)
        .with_has_header(true)
        .with_separator(b';')
        .with_skip_rows(1)
        .with_n_rows(Some(3))
        .finish()?
        .filter(col("value").gt(lit(10)))
        .collect()?;

    let mut source = df![
        "x" => [1i32, 2, 3, 4],
        "y" => [0.5f64, 1.5, 2.5, 3.5]
    ]?;
    let parquet_path =
        std::env::temp_dir().join("rkt-polars-lazy-scan-options.parquet");
    {
        let mut file = File::create(&parquet_path)?;
        ParquetWriter::new(&mut file).finish(&mut source)?;
    }

    let parquet_args = ScanArgsParquet {
        n_rows: Some(2),
        ..Default::default()
    };
    let parquet_out =
        LazyFrame::scan_parquet(&parquet_path, parquet_args)?.collect()?;

    println!("csv scan options shape={:?}", csv_out.shape());
    println!("{csv_out}");
    println!("parquet scan options shape={:?}", parquet_out.shape());
    println!("{parquet_out}");

    Ok(())
}
