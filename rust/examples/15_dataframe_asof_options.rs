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
    let exact = observations.join(
        &calibrations,
        ["time"],
        ["time"],
        JoinArgs::new(JoinType::AsOf(AsOfOptions {
            strategy: AsofStrategy::Backward,
            tolerance: Some(AnyValue::Int32(0)),
            ..Default::default()
        })),
    )?;

    let grouped_observations = df![
        "sensor" => ["a", "a", "b", "b"],
        "time" => [3i32, 5, 3, 5],
        "reading" => [300i32, 500, 30, 50]
    ]?;
    let grouped_calibrations = df![
        "sensor" => ["a", "a", "b", "b"],
        "time" => [1i32, 4, 1, 4],
        "offset" => [10i32, 40, 100, 400]
    ]?;
    let by_sensor = grouped_observations.join_asof_by(
        &grouped_calibrations,
        "time",
        "time",
        ["sensor"],
        ["sensor"],
        AsofStrategy::Backward,
        None,
    )?;

    println!(
        "exact offset sum={:?} nulls={}",
        exact.column("offset")?.i32()?.sum(),
        exact.column("offset")?.null_count()
    );
    println!(
        "by sensor offset sum={:?}",
        by_sensor.column("offset")?.i32()?.sum()
    );

    Ok(())
}
