use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let ints = Series::new("x", [Some(1i32), Some(2), None, Some(4)]);
    let floats = Series::new("f", [3.0f64, 7.5, 11.0]);

    let shifted = (ints.i32()? + 5).into_series();
    let scaled = (ints.i32()? * 3).into_series();
    let ratio = (floats.f64()? / 2.5).into_series();
    let remainder = (floats.f64()? % 2.0).into_series();

    println!(
        "shifted dtype={:?} row0={:?} row2={:?}",
        shifted.dtype(),
        shifted.i32()?.get(0),
        shifted.i32()?.get(2)
    );
    println!("scaled row3={:?}", scaled.i32()?.get(3));
    println!("ratio row1={:?}", ratio.f64()?.get(1));
    println!("remainder row1={:?}", remainder.f64()?.get(1));

    Ok(())
}
