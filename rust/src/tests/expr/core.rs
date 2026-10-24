use super::test_util::*;
use super::*;

#[test]
fn to_string_col_prints_plan() {
    let x = column("x");
    assert_eq!(take_cstring(expr_to_string(x)), "col(\"x\")");
    expr_drop(x);
}

#[test]
fn to_string_binary_prints_bracketed_tree() {
    let a = column("a");
    let b = column("b");
    let sum = expr_add(a, b);
    assert_eq!(
        take_cstring(expr_to_string(sum)),
        "[(col(\"a\")) + (col(\"b\"))]"
    );
    expr_drop(sum);
    expr_drop(b);
    expr_drop(a);
}

#[test]
fn to_string_alias_prints_alias_suffix() {
    let a = column("a");
    let b = aliased(a, "b");
    assert_eq!(take_cstring(expr_to_string(b)), "col(\"a\").alias(\"b\")");
    expr_drop(b);
    expr_drop(a);
}

#[test]
fn to_string_int_literal_prints_value() {
    let v = column("v");
    let ten = expr_lit_i32(10);
    let scaled = expr_mul(v, ten);
    assert_eq!(
        take_cstring(expr_to_string(scaled)),
        "[(col(\"v\")) * (dyn int: 10)]"
    );
    expr_drop(scaled);
    expr_drop(ten);
    expr_drop(v);
}

#[test]
fn to_string_null_expr_returns_null() {
    assert!(expr_to_string(ptr::null()).is_null());
}

#[test]
fn drop_count_increments_per_drop() {
    let before = expr_drop_count();
    let x = column("x");
    let y = column("y");
    expr_drop(x);
    expr_drop(y);
    expr_drop(ptr::null_mut());
    assert!(expr_drop_count() >= before + 2);
}

fn null_literal() -> Expr {
    let e = expr_lit_null();
    assert!(!e.is_null());
    let out = unsafe { (*e).clone() };
    expr_drop(e);
    out
}

#[test]
fn null_literal_is_a_null_of_dtype_null() {
    let out = DataFrame::empty()
        .lazy()
        .select([null_literal()])
        .collect()
        .unwrap();
    let v = out.column("literal").unwrap();
    assert_eq!(v.dtype(), &DataType::Null);
    assert_eq!((v.len(), v.null_count()), (1, 1));
}

#[test]
fn null_literal_broadcasts_and_compares_to_null() {
    let x = Column::new("x".into(), [Some(1i64), None, Some(3)]);
    let out = DataFrame::new_infer_height(vec![x])
        .unwrap()
        .lazy()
        .select([
            null_literal().alias("n"),
            col("x").eq(null_literal()).alias("eq"),
            col("x").eq_missing(null_literal()).alias("eq_missing"),
            (col("x") + null_literal()).alias("plus"),
        ])
        .collect()
        .unwrap();
    let n = out.column("n").unwrap();
    assert_eq!(
        (n.dtype(), n.len(), n.null_count()),
        (&DataType::Null, 3, 3)
    );
    let eq = out.column("eq").unwrap();
    assert_eq!((eq.dtype(), eq.null_count()), (&DataType::Boolean, 3));
    let missing: Vec<Option<bool>> = out
        .column("eq_missing")
        .unwrap()
        .bool()
        .unwrap()
        .iter()
        .collect();
    assert_eq!(missing, vec![Some(false), Some(true), Some(false)]);
    let plus = out.column("plus").unwrap();
    assert_eq!((plus.dtype(), plus.null_count()), (&DataType::Int64, 3));
}

fn u64_literal(v: u64) -> Expr {
    let e = expr_lit_u64(v);
    assert!(!e.is_null());
    let out = unsafe { (*e).clone() };
    expr_drop(e);
    out
}

#[test]
fn u64_literal_reaches_past_i64_and_compares_with_a_uint64_column() {
    let u = Column::new("u".into(), [u64::MAX, 1 << 63, 1]);
    let out = DataFrame::new_infer_height(vec![u])
        .unwrap()
        .lazy()
        .select([
            u64_literal(u64::MAX).alias("l"),
            col("u").eq(u64_literal(u64::MAX)).alias("eq"),
            col("u").gt_eq(u64_literal(1 << 63)).alias("ge"),
        ])
        .collect()
        .unwrap();
    let l = out.column("l").unwrap();
    assert_eq!(l.dtype(), &DataType::UInt64);
    assert_eq!(l.u64().unwrap().get(0), Some(u64::MAX));
    let bools = |name: &str| -> Vec<Option<bool>> {
        let c = out.column(name).unwrap();
        assert_eq!(c.dtype(), &DataType::Boolean);
        c.bool().unwrap().iter().collect()
    };
    assert_eq!(bools("eq"), vec![Some(true), Some(false), Some(false)]);
    assert_eq!(bools("ge"), vec![Some(true), Some(true), Some(false)]);
}
