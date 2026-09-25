use super::test_util::*;
use super::*;

fn dtype(tag: CompatDTypeTag) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    }
}

/// x: i32, y: f64, sepal_length: f64, species: str.
fn make_frame() -> (*mut DataFrame, Vec<*mut Series>) {
    let cols = vec![
        make_i32("x", &[1, 2]),
        make_f64("y", &[0.5, 1.5]),
        make_f64("sepal_length", &[5.1, 4.9]),
        make_str("species", &["a", "b"]),
    ];
    let df = make_df(&cols);
    (df, cols)
}

fn drop_frame(df: *mut DataFrame, cols: Vec<*mut Series>) {
    dataframe_drop(df);
    for c in cols {
        series_drop(c);
    }
}

/// Column names after `select(exprs)`; None when collect fails.
fn select_names(
    df: *mut DataFrame,
    exprs: &[*mut Expr],
) -> Option<Vec<String>> {
    let lf = dataframe_lazy(df);
    let ptrs: Vec<*const Expr> =
        exprs.iter().map(|e| *e as *const Expr).collect();
    let projected = lazyframe_select(lf, ptrs.as_ptr(), ptrs.len());
    assert!(!projected.is_null());
    let out = lazyframe_collect(projected);
    let names = if out.is_null() {
        None
    } else {
        let names = read_column_names(out);
        dataframe_drop(out);
        Some(names)
    };
    lazyframe_drop(projected);
    lazyframe_drop(lf);
    names
}

fn cstrs(names: &[&str]) -> (Vec<CString>, Vec<*const c_char>) {
    let owned: Vec<CString> = names.iter().map(|n| cstr(n)).collect();
    let ptrs = owned.iter().map(|c| c.as_ptr()).collect();
    (owned, ptrs)
}

fn exclude(e: *mut Expr, names: &[&str]) -> *mut Expr {
    let (_owned, ptrs) = cstrs(names);
    expr_exclude(e, ptrs.as_ptr(), ptrs.len())
}

fn col(name: &str) -> *mut Expr {
    let n = cstr(name);
    let e = expr_col(n.as_ptr());
    assert!(!e.is_null());
    e
}

fn check_select(exprs: &[*mut Expr], expected: &[&str]) {
    let (df, cols) = make_frame();
    assert_eq!(select_names(df, exprs), Some(strings(expected)));
    for e in exprs {
        expr_drop(*e);
    }
    drop_frame(df, cols);
}

fn strings(names: &[&str]) -> Vec<String> {
    names.iter().map(|s| s.to_string()).collect()
}

#[test]
fn all_selects_every_column_in_order() {
    check_select(&[expr_all()], &["x", "y", "sepal_length", "species"]);
}

#[test]
fn exclude_drops_named_columns() {
    let e = exclude(expr_all(), &["y", "species"]);
    assert!(!e.is_null());
    check_select(&[e], &["x", "sepal_length"]);
}

#[test]
fn exclude_by_regex_name() {
    let e = exclude(expr_all(), &["^sepal_.*$"]);
    assert!(!e.is_null());
    check_select(&[e], &["x", "y", "species"]);
}

#[test]
fn exclude_absent_name_is_noop() {
    let e = exclude(expr_all(), &["nope"]);
    assert!(!e.is_null());
    check_select(&[e], &["x", "y", "sepal_length", "species"]);
}

#[test]
fn exclude_on_dtype_col() {
    let e = exclude(expr_dtype_col(dtype(CompatDTypeTag::Float64)), &["y"]);
    assert!(!e.is_null());
    check_select(&[e], &["sepal_length"]);
}

#[test]
fn exclude_on_regex_col() {
    let e = exclude(col("^s.*$"), &["species"]);
    assert!(!e.is_null());
    check_select(&[e], &["sepal_length"]);
}

#[test]
fn exclude_without_expanding_input_returns_null() {
    let plain = col("x");
    assert!(exclude(plain, &["y"]).is_null());
    expr_drop(plain);
}

#[test]
fn exclude_null_input_returns_null() {
    assert!(exclude(ptr::null_mut(), &["y"]).is_null());
}

#[test]
fn exclude_zero_names_returns_null() {
    let e = expr_all();
    assert!(expr_exclude(e, ptr::null(), 0).is_null());
    expr_drop(e);
}

#[test]
fn multi_column_recognises_expanding_leaves() {
    let plain = col("x");
    let re = col("^s.*$");
    let wild = expr_all();
    let dt = expr_dtype_col(dtype(CompatDTypeTag::Int32));
    let alias = cstr("z");
    let over_wild = expr_alias(wild, alias.as_ptr());
    assert_eq!(expr_multi_column(plain), 0);
    assert_eq!(expr_multi_column(re), 1);
    assert_eq!(expr_multi_column(wild), 1);
    assert_eq!(expr_multi_column(dt), 1);
    assert_eq!(expr_multi_column(over_wild), 1);
    assert_eq!(expr_multi_column(ptr::null()), 0);
    for e in [plain, re, wild, dt, over_wild] {
        expr_drop(e);
    }
}

#[test]
fn dtype_col_selects_matching_columns() {
    check_select(
        &[expr_dtype_col(dtype(CompatDTypeTag::Float64))],
        &["y", "sepal_length"],
    );
    check_select(&[expr_dtype_col(dtype(CompatDTypeTag::Int32))], &["x"]);
    check_select(
        &[expr_dtype_col(dtype(CompatDTypeTag::String))],
        &["species"],
    );
    check_select(&[expr_dtype_col(dtype(CompatDTypeTag::Int64))], &[]);
}

#[test]
fn dtype_col_rejected_tag_returns_null() {
    assert!(expr_dtype_col(dtype(CompatDTypeTag::List)).is_null());
}

#[test]
fn regex_col_expands_in_schema_order() {
    check_select(&[col("^.*(?:s).*$")], &["sepal_length", "species"]);
}

#[test]
fn invalid_regex_collect_returns_null() {
    let (df, cols) = make_frame();
    let e = col("^(?=a)$");
    assert_eq!(select_names(df, &[e]), None);
    expr_drop(e);
    drop_frame(df, cols);
}
