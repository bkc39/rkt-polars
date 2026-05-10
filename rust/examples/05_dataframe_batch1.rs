use polars::prelude::*;
use std::fs::File;

fn main() -> PolarsResult<()> {
    let mut df = df![
        "uid" => [1i32, 2, 3, 4],
        "name" => ["alice", "bob", "carol", "dora"]
    ]?;
    let orders = df![
        "uid" => [1i32, 2, 2, 5],
        "amount" => [10i32, 20, 30, 40]
    ]?;

    let with_region =
        df.hstack(&[Series::new("region", ["east", "west", "west", "east"])])?;
    let semi =
        df.join(&orders, ["uid"], ["uid"], JoinArgs::new(JoinType::Semi))?;
    let anti =
        df.join(&orders, ["uid"], ["uid"], JoinArgs::new(JoinType::Anti))?;

    let parquet_path = std::env::temp_dir().join("rkt-polars-batch1.parquet");
    {
        let mut file = File::create(&parquet_path)?;
        ParquetWriter::new(&mut file).finish(&mut df)?;
    }
    let parquet_roundtrip =
        ParquetReader::new(File::open(&parquet_path)?).finish()?;

    let jsonl_path = std::env::temp_dir().join("rkt-polars-batch1.jsonl");
    {
        let mut file = File::create(&jsonl_path)?;
        JsonWriter::new(&mut file)
            .with_json_format(JsonFormat::JsonLines)
            .finish(&mut df)?;
    }
    let jsonl_roundtrip = JsonReader::new(File::open(&jsonl_path)?)
        .with_json_format(JsonFormat::JsonLines)
        .finish()?;

    println!("hstack shape={:?}", with_region.shape());
    println!("semi rows={}", semi.height());
    println!("anti rows={}", anti.height());
    println!("parquet shape={:?}", parquet_roundtrip.shape());
    println!("json lines shape={:?}", jsonl_roundtrip.shape());

    Ok(())
}
