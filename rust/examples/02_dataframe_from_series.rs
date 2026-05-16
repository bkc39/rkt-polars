use chrono::NaiveDate;
use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let users = Series::new("user", ["alice", "bob", "carol", "dora"]);
    let scores = Series::new("score", [10i32, 25, 18, 41]);
    let costs = Series::new("cost", [1.2f64, 3.5, 2.0, 8.4]);
    let created_at = Series::new(
        "created_at",
        [
            NaiveDate::from_ymd_opt(2024, 1, 1)
                .unwrap()
                .and_hms_opt(8, 0, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 1, 2)
                .unwrap()
                .and_hms_opt(8, 0, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 1, 3)
                .unwrap()
                .and_hms_opt(8, 0, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 1, 4)
                .unwrap()
                .and_hms_opt(8, 0, 0)
                .unwrap(),
        ],
    );

    let df = DataFrame::new(vec![users, scores, costs, created_at])?;

    println!("shape={:?}", df.shape());
    println!("height={} width={}", df.height(), df.width());
    println!("column names={:?}", df.get_column_names());

    for field in df.schema().iter_fields() {
        println!("schema {} => {:?}", field.name(), field.data_type());
    }

    let score = df.column("score")?;
    println!(
        "score column dtype={:?} len={} nulls={}",
        score.dtype(),
        score.len(),
        score.null_count()
    );

    Ok(())
}
