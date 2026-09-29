use super::test_util::*;
use super::*;

#[test]
fn meta_output_name_of_col_is_the_column() {
    let a = column("a");
    assert_eq!(take_cstring(expr_meta_output_name(a)), "a");
    expr_drop(a);
}

#[test]
fn meta_output_name_of_alias_is_the_alias() {
    let a = column("a");
    let b = aliased(a, "b");
    assert_eq!(take_cstring(expr_meta_output_name(b)), "b");
    expr_drop(b);
    expr_drop(a);
}

#[test]
fn meta_output_name_of_binary_is_the_left_leaf() {
    let a = column("a");
    let b = column("b");
    let sum = expr_add(a, b);
    assert_eq!(take_cstring(expr_meta_output_name(sum)), "a");
    expr_drop(sum);
    expr_drop(b);
    expr_drop(a);
}

#[test]
fn meta_output_name_of_literal_is_literal() {
    let two = expr_lit_i32(2);
    assert_eq!(take_cstring(expr_meta_output_name(two)), "literal");
    expr_drop(two);
}

#[test]
fn meta_output_name_of_wildcard_returns_null() {
    let w = Box::into_raw(Box::new(all().as_expr()));
    assert!(expr_meta_output_name(w).is_null());
    expr_drop(w);
}

#[test]
fn meta_output_name_null_expr_returns_null() {
    assert!(expr_meta_output_name(ptr::null()).is_null());
}

#[test]
fn meta_root_names_in_tree_order() {
    let a = column("a");
    let b = column("b");
    let sum = expr_add(a, b);
    assert_eq!(expr_meta_root_names_len(sum), 2);
    assert_eq!(take_cstring(expr_meta_root_name(sum, 0)), "a");
    assert_eq!(take_cstring(expr_meta_root_name(sum, 1)), "b");
    expr_drop(sum);
    expr_drop(b);
    expr_drop(a);
}

#[test]
fn meta_root_names_see_through_alias() {
    let a = column("a");
    let t = aliased(a, "t");
    assert_eq!(expr_meta_root_names_len(t), 1);
    assert_eq!(take_cstring(expr_meta_root_name(t, 0)), "a");
    expr_drop(t);
    expr_drop(a);
}

#[test]
fn meta_root_names_of_literal_is_empty() {
    let two = expr_lit_i32(2);
    assert_eq!(expr_meta_root_names_len(two), 0);
    expr_drop(two);
}

#[test]
fn meta_root_name_out_of_range_returns_null() {
    let a = column("a");
    assert!(expr_meta_root_name(a, 1).is_null());
    expr_drop(a);
}

#[test]
fn meta_root_names_len_null_expr_is_zero() {
    assert_eq!(expr_meta_root_names_len(ptr::null()), 0);
    assert!(expr_meta_root_name(ptr::null(), 0).is_null());
}

#[test]
fn meta_eq_reflexive() {
    let a = column("a");
    assert_eq!(expr_meta_eq(a, a), 1);
    expr_drop(a);
}

#[test]
fn meta_eq_structural_over_distinct_boxes() {
    let a1 = column("a");
    let a2 = column("a");
    assert_eq!(expr_meta_eq(a1, a2), 1);
    expr_drop(a2);
    expr_drop(a1);
}

#[test]
fn meta_eq_distinguishes_names() {
    let a = column("a");
    let b = column("b");
    assert_eq!(expr_meta_eq(a, b), 0);
    expr_drop(b);
    expr_drop(a);
}

#[test]
fn meta_eq_null_returns_zero() {
    let a = column("a");
    assert_eq!(expr_meta_eq(a, ptr::null()), 0);
    assert_eq!(expr_meta_eq(ptr::null(), a), 0);
    expr_drop(a);
}
