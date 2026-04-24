use polars::prelude::*;
use std::fs::File;

fn main() -> PolarsResult<()> {
    let mut original = df![
        "city" => ["Boston", "New York", "Chicago"],
        "population_millions" => [0.65f64, 8.8, 2.7],
        "founded" => [1630i32, 1624, 1837]
    ]?;

    let csv_path = std::env::temp_dir().join("rkt-polars-example.csv");

    {
        let mut file = File::create(&csv_path)?;
        CsvWriter::new(&mut file)
            .include_header(true)
            .with_separator(b',')
            .finish(&mut original)?;
    }

    let file = File::open(&csv_path)?;
    let roundtrip = CsvReadOptions::default()
        .with_has_header(true)
        .into_reader_with_file_handle(file)
        .finish()?;

    println!("wrote csv to {}", csv_path.display());
    println!("roundtrip shape={:?}", roundtrip.shape());
    println!("roundtrip columns={:?}", roundtrip.get_column_names());
    println!("roundtrip:\n{roundtrip}");

    Ok(())
}
