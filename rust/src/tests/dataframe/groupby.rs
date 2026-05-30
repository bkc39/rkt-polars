use super::test_util::*;
use super::*;

/// Wrap the by/agg name array setup that every group-by call
/// reuses, then read back the `x` column sorted by `g`.
fn run_group_by(
    df: *mut DataFrame,
    agg_name: &str,
    f: extern "C" fn(
        *mut DataFrame,
        *const *const c_char,
        usize,
        *const *const c_char,
        usize,
    ) -> *mut DataFrame,
) -> *mut DataFrame {
    let by_g = cstr("g");
    let by_arr: [*const c_char; 1] = [by_g.as_ptr()];
    let agg = cstr(agg_name);
    let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
    let out = f(
        df,
        by_arr.as_ptr(),
        by_arr.len(),
        agg_arr.as_ptr(),
        agg_arr.len(),
    );
    assert!(!out.is_null(), "group_by returned null");
    out
}

/// Sort the group-by result by `g` so the test reads back in a
/// deterministic order — Polars' group_by output ordering is
/// not guaranteed.
fn sorted_by_g(df: *mut DataFrame) -> *mut DataFrame {
    let g = cstr("g");
    let by: [*const c_char; 1] = [g.as_ptr()];
    dataframe_sort(df, by.as_ptr(), ptr::null(), by.len())
}

// Polars 0.41 renames the aggregated column by suffixing the
// op name — `group_by_sum` on column `x` produces `x_sum`, etc.

#[test]
fn group_by_sum_aggregates_per_key() {
    let (df, gs, xs) = make_gx();
    let raw = run_group_by(df, "x", dataframe_group_by_sum);
    let out = sorted_by_g(raw);
    assert_eq!(dataframe_height(out), 2);
    // a -> 10+20 = 30; b -> 30+40+50 = 120.
    assert_eq!(read_i32_col(out, "x_sum"), vec![30, 120]);
    dataframe_drop(out);
    dataframe_drop(raw);
    dataframe_drop(df);
    series_drop(gs);
    series_drop(xs);
}

#[test]
fn group_by_min_and_max() {
    let (df, gs, xs) = make_gx();
    let raw_min = run_group_by(df, "x", dataframe_group_by_min);
    let out_min = sorted_by_g(raw_min);
    assert_eq!(read_i32_col(out_min, "x_min"), vec![10, 30]);
    dataframe_drop(out_min);
    dataframe_drop(raw_min);

    let raw_max = run_group_by(df, "x", dataframe_group_by_max);
    let out_max = sorted_by_g(raw_max);
    assert_eq!(read_i32_col(out_max, "x_max"), vec![20, 50]);
    dataframe_drop(out_max);
    dataframe_drop(raw_max);

    dataframe_drop(df);
    series_drop(gs);
    series_drop(xs);
}

#[test]
fn group_by_mean_produces_f64_column() {
    let (df, gs, xs) = make_gx();
    let raw = run_group_by(df, "x", dataframe_group_by_mean);
    let out = sorted_by_g(raw);
    // a -> 15.0, b -> 40.0
    let n = cstr("x_mean");
    let col = dataframe_column(out, n.as_ptr());
    assert!(!col.is_null(), "x_mean column missing");
    assert_eq!(series_ref_f64(col, 0).value, 15.0);
    assert_eq!(series_ref_f64(col, 1).value, 40.0);
    series_drop(col);
    dataframe_drop(out);
    dataframe_drop(raw);
    dataframe_drop(df);
    series_drop(gs);
    series_drop(xs);
}

#[test]
fn group_by_count_emits_count_column() {
    let (df, gs, xs) = make_gx();
    // count produces a "<col>_count" column of u32 — the
    // outgoing column name carries the agg suffix from Polars.
    let by = cstr("g");
    let by_arr: [*const c_char; 1] = [by.as_ptr()];
    let agg = cstr("x");
    let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
    let raw = dataframe_group_by_count(
        df,
        by_arr.as_ptr(),
        by_arr.len(),
        agg_arr.as_ptr(),
        agg_arr.len(),
    );
    assert!(!raw.is_null());
    let out = sorted_by_g(raw);
    assert_eq!(dataframe_height(out), 2);
    // Either "x_count" or "x" depending on Polars version —
    // verify the row counts via the second column rather than a
    // hard-coded name.
    let names = read_column_names(out);
    assert_eq!(names.len(), 2);
    let val_name = cstr(&names[1]);
    let col = dataframe_column(out, val_name.as_ptr());
    // group `a` has 2 rows, group `b` has 3 rows. The exact int
    // type Polars picks (u32) is read via the u32 accessor.
    assert_eq!(series_ref_u32(col, 0).value, 2);
    assert_eq!(series_ref_u32(col, 1).value, 3);
    series_drop(col);
    dataframe_drop(out);
    dataframe_drop(raw);
    dataframe_drop(df);
    series_drop(gs);
    series_drop(xs);
}

#[test]
fn group_by_unknown_key_returns_null() {
    let (df, gs, xs) = make_gx();
    let by = cstr("nope");
    let by_arr: [*const c_char; 1] = [by.as_ptr()];
    let agg = cstr("x");
    let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
    let out = dataframe_group_by_sum(
        df,
        by_arr.as_ptr(),
        by_arr.len(),
        agg_arr.as_ptr(),
        agg_arr.len(),
    );
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(gs);
    series_drop(xs);
}

#[test]
fn group_by_null_df_returns_null() {
    let by = cstr("g");
    let by_arr: [*const c_char; 1] = [by.as_ptr()];
    let agg = cstr("x");
    let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
    assert!(dataframe_group_by_sum(
        ptr::null_mut(),
        by_arr.as_ptr(),
        by_arr.len(),
        agg_arr.as_ptr(),
        agg_arr.len()
    )
    .is_null());
}
