use chrono::NaiveDate;
use polars::prelude::*;

fn describe_series(series: &Series) {
    println!(
        "name={:?} len={} dtype={:?} nulls={}",
        series.name(),
        series.len(),
        series.dtype(),
        series.null_count()
    );
}

fn main() -> PolarsResult<()> {
    let ints = Series::new("ints", [1i32, 2, 3, 4]);
    let floats = Series::new("floats", [1.5f64, 2.0, 4.25, 8.0]);
    let strings = Series::new("strings", ["alpha", "beta", "gamma", "delta"]);
    let datetimes = Series::new(
        "timestamps",
        [
            NaiveDate::from_ymd_opt(2024, 1, 1)
                .unwrap()
                .and_hms_opt(9, 0, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 1, 2)
                .unwrap()
                .and_hms_opt(9, 30, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 1, 3)
                .unwrap()
                .and_hms_opt(10, 0, 0)
                .unwrap(),
            NaiveDate::from_ymd_opt(2024, 1, 4)
                .unwrap()
                .and_hms_opt(10, 30, 0)
                .unwrap(),
        ],
    );

    describe_series(&ints);
    describe_series(&floats);
    describe_series(&strings);
    describe_series(&datetimes);

    let mut renamed = ints.clone();
    renamed.rename("ints_renamed");
    describe_series(&renamed);

    let int_sum = ints.i32()?.sum();
    let float_mean = floats.f64()?.mean();
    let float_max = floats.f64()?.max();

    println!("int sum = {:?}", int_sum);
    println!("float mean = {:?}", float_mean);
    println!("float max = {:?}", float_max);

    Ok(())
}
