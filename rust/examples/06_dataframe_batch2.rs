use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let observations = df![
        "time" => [1i32, 3, 5],
        "reading" => [100i32, 300, 500]
    ]?;
    let calibrations = df![
        "time" => [1i32, 2, 4],
        "offset" => [10i32, 20, 40]
    ]?;

    let asof = observations.join(
        &calibrations,
        ["time"],
        ["time"],
        JoinArgs::new(JoinType::AsOf(AsOfOptions {
            strategy: AsofStrategy::Backward,
            ..Default::default()
        })),
    )?;

    let sales = df![
        "store" => ["a", "a", "b", "b"],
        "quarter" => ["q1", "q2", "q1", "q2"],
        "sales" => [10i32, 20, 30, 40]
    ]?;
    let pivoted = polars::lazy::frame::pivot::pivot_stable(
        &sales,
        ["quarter"],
        Some(["store"]),
        Some(["sales"]),
        true,
        Some(col("").sum()),
        None,
    )?;
    let unpivoted = pivoted.unpivot(["q1", "q2"], ["store"])?;

    println!("asof shape={:?}", asof.shape());
    println!("pivot columns={:?}", pivoted.get_column_names());
    println!("unpivot shape={:?}", unpivoted.shape());

    Ok(())
}
