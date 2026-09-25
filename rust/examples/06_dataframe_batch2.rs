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
        JoinArgs::new(JoinType::AsOf(Box::new(AsOfOptions {
            strategy: AsofStrategy::Backward,
            ..Default::default()
        }))),
        None,
    )?;

    let sales = df![
        "store" => ["a", "a", "b", "b"],
        "quarter" => ["q1", "q2", "q1", "q2"],
        "sales" => [10i32, 20, 30, 40]
    ]?;
    let quarters = sales.select(["quarter"])?.unique_stable(
        None,
        UniqueKeepStrategy::First,
        None,
    )?;
    let pivoted = sales
        .clone()
        .lazy()
        .pivot(
            cols(["quarter"]),
            Arc::new(quarters),
            cols(["store"]),
            cols(["sales"]),
            element().sum(),
            true,
            "_".into(),
            Default::default(),
        )
        .collect()?;
    let unpivoted = pivoted.unpivot(Some(["q1", "q2"]), ["store"])?;

    println!("asof shape={:?}", asof.shape());
    println!("pivot columns={:?}", pivoted.get_column_names());
    println!("unpivot shape={:?}", unpivoted.shape());

    Ok(())
}
