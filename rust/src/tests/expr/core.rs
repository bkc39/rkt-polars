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
