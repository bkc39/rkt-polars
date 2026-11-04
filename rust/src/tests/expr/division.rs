use super::test_util::take_box;
use super::*;

const TWO_TO_63: u64 = 1 << 63;

fn div(a: Expr, b: Expr) -> Expr {
    take_box(expr_div(&a, &b)).expect("expr_div returned null")
}

pub(super) fn div_plan(a: &str, b: &str) -> String {
    format!("[({a}) rust_div ({b})].floor_if_integer([{a}, {b}])")
}

fn frame() -> LazyFrame {
    let mut df = df![
        "g" => ["x", "x", "y"],
        "i" => [10i64, -7, 9],
        "u" => [3u64, 2, 2],
        "f" => [10.0f64, -7.0, 9.0],
        "b" => [3u8, 200, 7],
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

fn int64s(xs: &[i64]) -> (DataType, Vec<AnyValue<'static>>) {
    (
        DataType::Int64,
        xs.iter().map(|&x| AnyValue::Int64(x)).collect(),
    )
}

fn nested(depth: usize, step: impl Fn(Expr) -> Expr) -> Expr {
    (0..depth).fold(col("i"), |e, _| div(step(e), lit(1)))
}

#[test]
fn integer_quotient_floors_beside_uint64() {
    let df = selected(vec![
        div(col("i"), col("u")).alias("columns"),
        div(col("i"), lit(TWO_TO_63)).alias("literal"),
        div(col("f"), col("u")).alias("float"),
        div(col("i"), lit(2i32)).alias("int64"),
        div(div(col("i"), col("u")), col("u")).alias("nested"),
    ]);
    assert_eq!(values(&df, "columns"), floats(&[3.0, -4.0, 4.0]));
    assert_eq!(values(&df, "literal"), floats(&[0.0, -1.0, 0.0]));
    assert_eq!(values(&df, "float"), floats(&[10.0 / 3.0, -3.5, 4.5]));
    assert_eq!(values(&df, "int64"), int64s(&[5, -4, 4]));
    assert_eq!(values(&df, "nested"), floats(&[1.0, -2.0, 2.0]));
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
    let df = selected(vec![div(col("^(i|f)$"), lit(TWO_TO_63))]);
    assert_eq!(values(&df, "i"), floats(&[0.0, -1.0, 0.0]));
    assert_eq!(
        values(&df, "f").1[0],
        AnyValue::Float64(10.0 / TWO_TO_63 as f64)
    );
    assert_eq!(
        quotient.to_string(),
        div_plan("cs.matches(\"^(i|f)$\")", "col(\"u\")")
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

#[test]
fn nested_quotients_grow_polynomially() {
    let steps: [fn(Expr) -> Expr; 2] = [|e| e, |e| e.abs()];
    for step in steps {
        let length = |depth| nested(depth, step).to_string().len();
        assert!(length(16) < 20 * length(4), "{} {}", length(16), length(4));
    }
    let df = selected(vec![
        nested(16, |e| e),
        nested(16, |e| e.abs()).alias("abs"),
    ]);
    assert_eq!(values(&df, "i"), int64s(&[10, -7, 9]));
    assert_eq!(values(&df, "abs"), int64s(&[10, 7, 9]));
}

#[test]
fn integer_quotient_keeps_the_typing_of_a_literal() {
    let df = selected(vec![
        div(col("b"), lit(3)).alias("u8"),
        div(lit(300), col("b")).alias("u16"),
        div(lit(-7), col("u")).alias("i64"),
        div(col("b"), lit(-1)).alias("i16"),
        div(col("b").abs(), lit(3)).alias("abs"),
    ]);
    let dtypes: Vec<DataType> = ["u8", "u16", "i64", "i16", "abs"]
        .iter()
        .map(|name| df.column(name).unwrap().dtype().clone())
        .collect();
    use DataType::*;
    assert_eq!(dtypes, [UInt8, UInt16, Int64, Int16, UInt8]);
}

fn ints_as(dtype: DataType, xs: &[i64]) -> (DataType, Vec<AnyValue<'static>>) {
    let s = Series::new("".into(), xs).cast(&dtype).unwrap();
    (dtype, s.iter().map(|v| v.into_static()).collect())
}

#[test]
fn literal_quotient_keeps_dynamic_typing() {
    let half = || div(lit(7), lit(2));
    let df = selected(vec![
        (half() + col("u")).alias("u64"),
        (half() + col("b")).alias("u8"),
        (col("b") * div(lit(10), lit(3))).alias("wrapped"),
        (div(lit(TWO_TO_63), lit(2)) + col("u")).alias("big"),
        div(half(), col("u")).alias("quotient"),
        (div(lit(-7), lit(TWO_TO_63)) + col("b")).alias("i16"),
        div(lit(-7), lit(2)).alias("floored"),
    ]);
    use DataType::*;
    let quarter = 1i64 << 62;
    assert_eq!(values(&df, "u64"), ints_as(UInt64, &[6, 5, 5]));
    assert_eq!(values(&df, "u8"), ints_as(UInt8, &[6, 203, 10]));
    assert_eq!(values(&df, "wrapped"), ints_as(UInt8, &[9, 88, 21]));
    assert_eq!(
        values(&df, "big"),
        ints_as(UInt64, &[quarter + 3, quarter + 2, quarter + 2])
    );
    assert_eq!(values(&df, "quotient"), ints_as(UInt64, &[1, 1, 1]));
    assert_eq!(values(&df, "i16"), ints_as(Int16, &[2, 199, 6]));
    assert_eq!(values(&df, "floored"), ints_as(Int32, &[-4, -4, -4]));
}

#[test]
fn integer_quotient_of_compound_operands_floors() {
    let df = selected(vec![
        div(div(col("i"), col("u")).abs(), col("u")).alias("float"),
        div(div(col("i"), lit(2)).abs(), col("u")).alias("integer"),
        div(col("i").abs() + col("i"), col("u")).alias("sum"),
    ]);
    assert_eq!(values(&df, "float"), floats(&[1.0, 2.0, 2.0]));
    assert_eq!(values(&df, "integer"), floats(&[1.0, 2.0, 2.0]));
    assert_eq!(values(&df, "sum"), floats(&[6.0, 0.0, 9.0]));
    let compound = div(col("i").sum(), col("u"));
    assert_eq!(
        compound.to_string(),
        "[(col(\"i\").sum()) rust_div (col(\"u\"))]\
         .floor_if_integer([null.cast(dtype_of(col(\"i\").sum())), \
         col(\"u\")])"
    );
}
