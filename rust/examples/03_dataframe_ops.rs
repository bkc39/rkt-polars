use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let df = df![
        "group" => ["a", "a", "b", "b", "c"],
        "value" => [10i32, 25, 7, 30, 18],
        "cost" => [1.2f64, 2.4, 0.5, 3.1, 1.8]
    ]?;

    println!("input:\n{df}");

    let value_mask = df.column("value")?.i32()?.gt(15);
    let filtered = df.filter(&value_mask)?;
    println!("filtered value > 15:\n{filtered}");

    let sorted = df.sort(
        ["group", "value"],
        SortMultipleOptions::new().with_order_descending_multi([false, true]),
    )?;
    println!("sorted by group asc, value desc:\n{sorted}");

    #[allow(deprecated)]
    let grouped = df.group_by(["group"])?.select(["value"]).sum()?;
    println!("grouped sum(value):\n{grouped}");

    Ok(())
}
