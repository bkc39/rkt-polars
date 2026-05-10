use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let wide = Series::new("wide", [Some(1_099_511_627_776i64), None, Some(4)]);
    let count = Series::new("count", [Some(1u32), Some(2), None, Some(7)]);
    let big = Series::new("big", [10u64, 20, 4_294_967_296]);

    println!(
        "wide sum={:?} min={:?} max={:?} mean={:?}",
        wide.i64()?.sum(),
        wide.i64()?.min(),
        wide.i64()?.max(),
        wide.i64()?.mean()
    );
    println!(
        "count sum={:?} min={:?} max={:?} mean={:?}",
        count.u32()?.sum(),
        count.u32()?.min(),
        count.u32()?.max(),
        count.u32()?.mean()
    );
    println!(
        "big sum={:?} min={:?} max={:?} mean={:?}",
        big.u64()?.sum(),
        big.u64()?.min(),
        big.u64()?.max(),
        big.u64()?.mean()
    );

    Ok(())
}
