use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let i8s = Series::new("i8s", [Some(-8i8), None, Some(12)]);
    let i16s = Series::new("i16s", [Some(-300i16), None, Some(1200)]);
    let u8s = Series::new("u8s", [Some(0u8), None, Some(255)]);
    let u16s = Series::new("u16s", [Some(0u16), None, Some(65_535)]);
    let f32s = Series::new("f32s", [Some(1.5f32), None, Some(2.25)]);

    let df = DataFrame::new(vec![
        i8s.clone(),
        i16s.clone(),
        u8s.clone(),
        u16s.clone(),
        f32s.clone(),
    ])?;

    println!("primitive dtype shape={:?}", df.shape());
    println!("{df}");
    println!(
        "i8 dtype={:?} ref0={:?} sum={:?} mean={:?}",
        i8s.dtype(),
        i8s.i8()?.get(0),
        i8s.i8()?.sum(),
        i8s.i8()?.mean()
    );
    println!(
        "i16 dtype={:?} ref2={:?} max={:?}",
        i16s.dtype(),
        i16s.i16()?.get(2),
        i16s.i16()?.max()
    );
    println!(
        "u8 dtype={:?} ref2={:?} max={:?}",
        u8s.dtype(),
        u8s.u8()?.get(2),
        u8s.u8()?.max()
    );
    println!(
        "u16 dtype={:?} ref2={:?} max={:?}",
        u16s.dtype(),
        u16s.u16()?.get(2),
        u16s.u16()?.max()
    );
    println!(
        "f32 dtype={:?} ref0={:?} sum={:?}",
        f32s.dtype(),
        f32s.f32()?.get(0),
        f32s.f32()?.sum()
    );

    Ok(())
}
