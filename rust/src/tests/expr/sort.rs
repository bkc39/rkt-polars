use super::test_util::*;
use super::*;

fn frame() -> (*mut DataFrame, [*mut Series; 2]) {
    let a = make_opt_i32("a", &[Some(1), None, Some(1), None]);
    let b = make_opt_i32("b", &[None, Some(2), Some(3), None]);
    (make_df(&[a, b]), [a, b])
}

fn release(df: *mut DataFrame, cols: [*mut Series; 2]) {
    dataframe_drop(df);
    for c in cols {
        series_drop(c);
    }
}

fn collect_plan(lf: *mut LazyFrame) -> *mut DataFrame {
    assert!(!lf.is_null());
    let out = lazyframe_collect(lf);
    lazyframe_drop(lf);
    assert!(!out.is_null(), "{:?}", recorded_error());
    out
}

fn select(df: *mut DataFrame, e: *mut Expr) -> *mut DataFrame {
    let lf = dataframe_lazy(df);
    let exprs: [*const Expr; 1] = [e];
    let out = collect_plan(lazyframe_select(lf, exprs.as_ptr(), 1));
    lazyframe_drop(lf);
    expr_drop(e);
    out
}

#[test]
fn expr_sort_places_nulls_by_flag() {
    let (df, cols) = frame();
    let cases: [(u8, u8, [Option<i32>; 4]); 4] = [
        (0, 0, [None, None, Some(2), Some(3)]),
        (0, 1, [Some(2), Some(3), None, None]),
        (1, 0, [None, None, Some(3), Some(2)]),
        (1, 1, [Some(3), Some(2), None, None]),
    ];
    for (descending, nulls_last, expected) in cases {
        let b = column("b");
        let out = select(df, expr_sort_with_options(b, descending, nulls_last));
        expr_drop(b);
        assert_eq!(read_opt_i32_col(out, "b"), expected.to_vec());
        dataframe_drop(out);
    }
    release(df, cols);
}

#[test]
fn expr_sort_by_places_nulls_per_key() {
    let (df, cols) = frame();
    let (a, b) = (column("a"), column("b"));
    let by: [*const Expr; 2] = [a, b];
    let sorted = expr_sort_by_with_options(
        b,
        by.as_ptr(),
        [0, 0].as_ptr(),
        [1, 0].as_ptr(),
        2,
        1,
    );
    assert!(!sorted.is_null());
    let out = select(df, sorted);
    assert_eq!(
        read_opt_i32_col(out, "b"),
        vec![None, Some(3), None, Some(2)]
    );
    dataframe_drop(out);
    expr_drop(a);
    expr_drop(b);
    release(df, cols);
}

#[test]
fn expr_sort_by_without_keys_returns_null() {
    let b = column("b");
    let by: [*const Expr; 0] = [];
    assert!(expr_sort_by_with_options(
        b,
        by.as_ptr(),
        ptr::null(),
        ptr::null(),
        0,
        0
    )
    .is_null());
    expr_drop(b);
}

#[test]
fn lazyframe_sort_places_nulls_per_key() {
    let (df, cols) = frame();
    let (na, nb) = (cstr("a"), cstr("b"));
    let names: [*const c_char; 2] = [na.as_ptr(), nb.as_ptr()];
    let lf = dataframe_lazy(df);
    let sorted = lazyframe_sort_with_options(
        lf,
        names.as_ptr(),
        [0, 1].as_ptr(),
        [1, 1].as_ptr(),
        2,
        1,
    );
    lazyframe_drop(lf);
    let out = collect_plan(sorted);
    assert_eq!(
        read_opt_i32_col(out, "a"),
        vec![Some(1), Some(1), None, None]
    );
    assert_eq!(
        read_opt_i32_col(out, "b"),
        vec![Some(3), None, Some(2), None]
    );
    dataframe_drop(out);
    release(df, cols);
}

#[test]
fn expr_sort_of_booleans_places_nulls_by_flag() {
    let (t, f) = (Some(true), Some(false));
    let b = make_opt_bool("b", &[t, None, f, t]);
    let df = make_df(&[b]);
    let cases = [
        (0, 1, [f, t, t, None]),
        (1, 0, [None, t, t, f]),
        (1, 1, [t, t, f, None]),
    ];
    for (descending, nulls_last, expected) in cases {
        let e = column("b");
        let out = select(df, expr_sort_with_options(e, descending, nulls_last));
        expr_drop(e);
        assert_eq!(read_opt_bool_col(out, "b"), expected.to_vec());
        dataframe_drop(out);
    }
    dataframe_drop(df);
    series_drop(b);
}

#[test]
fn expr_sort_of_a_sorted_column_honours_nulls_last() {
    let x = make_opt_i32("x", &[Some(3), None, Some(1), None, Some(2)]);
    let df = make_df(&[x]);
    let key = cstr("x");
    let names: [*const c_char; 1] = [key.as_ptr()];
    let lf = dataframe_lazy(df);
    let once = collect_plan(lazyframe_sort_with_options(
        lf,
        names.as_ptr(),
        [0].as_ptr(),
        [0].as_ptr(),
        1,
        0,
    ));
    lazyframe_drop(lf);
    let e = column("x");
    let out = select(once, expr_sort_with_options(e, 0, 1));
    expr_drop(e);
    assert_eq!(
        read_opt_i32_col(out, "x"),
        vec![Some(1), Some(2), Some(3), None, None]
    );
    for p in [out, once, df] {
        dataframe_drop(p);
    }
    series_drop(x);
}

#[test]
fn lazy_sort_then_projection_handles_booleans() {
    let a = make_i32("a", &[2, 1, 2]);
    let b = make_opt_bool("b", &[Some(true), None, Some(false)]);
    let df = make_df(&[a, b]);
    let key = cstr("b");
    let names: [*const c_char; 1] = [key.as_ptr()];
    let lf = dataframe_lazy(df);
    let sorted = lazyframe_sort_with_options(
        lf,
        names.as_ptr(),
        [0].as_ptr(),
        [1].as_ptr(),
        1,
        0,
    );
    let e = column("b");
    let exprs: [*const Expr; 1] = [e];
    let out = collect_plan(lazyframe_select(sorted, exprs.as_ptr(), 1));
    assert_eq!(
        read_opt_bool_col(out, "b"),
        vec![Some(false), Some(true), None]
    );
    expr_drop(e);
    lazyframe_drop(sorted);
    lazyframe_drop(lf);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(a);
    series_drop(b);
}
