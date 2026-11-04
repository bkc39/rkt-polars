use super::*;

fn div(a: Expr, b: Expr) -> Expr {
    let (a, b) = (Box::into_raw(Box::new(a)), Box::into_raw(Box::new(b)));
    let out = expr_div(a, b);
    assert!(!out.is_null());
    let quotient = unsafe { (*out).clone() };
    for e in [out, a, b] {
        expr_drop(e);
    }
    quotient
}

fn frame() -> LazyFrame {
    let mut df = df![
        "g" => ["x", "x", "y"],
        "i" => [10i64, -7, 9],
        "u" => [3u64, 2, 2],
        "f" => [10.0f64, -7.0, 9.0],
    ]
    .unwrap();
    df.with_column(Column::full_null("n".into(), 3, &DataType::Null))
        .unwrap();
    df.lazy()
}

fn selected(exprs: Vec<Expr>) -> DataFrame {
    frame().select(exprs).collect().unwrap()
}

fn values(df: &DataFrame, name: &str) -> (DataType, Vec<AnyValue<'static>>) {
    let c = df.column(name).unwrap();
    let values = (0..c.len())
        .map(|i| c.get(i).unwrap().into_static())
        .collect();
    (c.dtype().clone(), values)
}

fn floats(xs: &[f64]) -> (DataType, Vec<AnyValue<'static>>) {
    (
        DataType::Float64,
        xs.iter().map(|&x| AnyValue::Float64(x)).collect(),
    )
}

#[test]
fn integer_quotient_floors_beside_uint64() {
    let df = selected(vec![
        div(col("i"), col("u")).alias("columns"),
        div(col("i"), lit(1u64 << 63)).alias("literal"),
        div(col("f"), col("u")).alias("float"),
        div(col("i"), lit(2i32)).alias("int64"),
    ]);
    assert_eq!(values(&df, "columns"), floats(&[3.0, -4.0, 4.0]));
    assert_eq!(values(&df, "literal"), floats(&[0.0, -1.0, 0.0]));
    assert_eq!(values(&df, "float"), floats(&[10.0 / 3.0, -3.5, 4.5]));
    assert_eq!(
        values(&df, "int64"),
        (
            DataType::Int64,
            vec![AnyValue::Int64(5), AnyValue::Int64(-4), AnyValue::Int64(4)]
        )
    );
}

#[test]
fn integer_quotient_floors_each_expanded_column() {
    let quotient = div(col("^(i|f)$"), col("u"));
    let df = selected(vec![quotient.clone()]);
    let names: Vec<&str> =
        df.get_column_names().iter().map(|n| n.as_str()).collect();
    assert_eq!(names, ["i", "f"]);
    assert_eq!(values(&df, "i"), floats(&[3.0, -4.0, 4.0]));
    assert_eq!(values(&df, "f"), floats(&[10.0 / 3.0, -3.5, 4.5]));
    let df = selected(vec![div(col("^(i|f)$"), lit(1u64 << 63))]);
    assert_eq!(values(&df, "i"), floats(&[0.0, -1.0, 0.0]));
    assert_eq!(
        values(&df, "f").1[0],
        AnyValue::Float64(10.0 / 9223372036854775808.0)
    );
    assert_eq!(
        quotient.to_string(),
        "[(cs.matches(\"^(i|f)$\")) rust_div (col(\"u\"))]\
         .floor_if_integer([cs.matches(\"^(i|f)$\"), col(\"u\")])"
    );
}

#[test]
fn integer_quotient_floors_in_groups() {
    let df = frame()
        .group_by_stable([col("g")])
        .agg([
            div(col("i").sum(), col("u").sum()).alias("totals"),
            div(col("i"), col("u").sum()).alias("rows"),
        ])
        .collect()
        .unwrap();
    assert_eq!(values(&df, "totals"), floats(&[0.0, 4.0]));
    let rows = df.column("rows").unwrap().list().unwrap().clone();
    let x = rows.get_as_series(0).unwrap();
    assert_eq!(x.f64().unwrap().to_vec(), [Some(2.0), Some(-2.0)]);
    let over = selected(vec![div(col("i"), col("u").sum())
        .over([col("g")])
        .unwrap()
        .alias("over")]);
    assert_eq!(values(&over, "over"), floats(&[2.0, -2.0, 4.0]));
}

#[test]
fn integer_quotient_beside_a_null_column_is_null() {
    let df = selected(vec![
        div(lit(3i32), col("n")).alias("left"),
        div(col("n"), col("u")).alias("right"),
    ]);
    let nulls = vec![AnyValue::Null, AnyValue::Null, AnyValue::Null];
    assert_eq!(values(&df, "left"), (DataType::Int32, nulls.clone()));
    assert_eq!(values(&df, "right"), (DataType::UInt64, nulls));
}
