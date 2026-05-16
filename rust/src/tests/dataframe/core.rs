use super::test_util::*;
use super::*;

/// Build a tiny 2-column DataFrame: i32 `x` + str `g`. Returns
/// the DataFrame and the input Series so the caller can drop
/// everything cleanly.
fn make_xg(
    x: &[i32],
    g: &[&str],
) -> (*mut DataFrame, *mut Series, *mut Series) {
    let xs = make_i32("x", x);
    let gs = make_str("g", g);
    let df = make_df(&[xs, gs]);
    (df, xs, gs)
}

// --- lifecycle / construction -------------------------------------

#[test]
fn empty_dataframe_has_zero_shape() {
    let df = dataframe_empty();
    assert!(!df.is_null());
    assert_eq!(dataframe_height(df), 0);
    assert_eq!(dataframe_width(df), 0);
    dataframe_drop(df);
}

#[test]
fn dataframe_make_and_drop_no_op() {
    // `dataframe_make` produces a default DataFrame and the
    // matching drop must accept a null pointer without panicking.
    let df = dataframe_make();
    assert!(!df.is_null());
    dataframe_drop(df);
    dataframe_drop(ptr::null_mut());
}

#[test]
fn dataframe_new_with_columns_sets_shape() {
    let (df, xs, gs) = make_xg(&[1, 2, 3], &["a", "b", "c"]);
    assert_eq!(dataframe_height(df), 3);
    assert_eq!(dataframe_width(df), 2);
    let sh = dataframe_shape(df);
    assert_eq!(sh.rows, 3);
    assert_eq!(sh.cols, 2);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn dataframe_new_null_ptr_array_returns_null() {
    let df = dataframe_new(ptr::null(), 3);
    assert!(df.is_null());
}

#[test]
fn dataframe_new_with_null_series_in_array_returns_null() {
    let xs = make_i32("x", &[1, 2]);
    let ptrs: [*const Series; 2] = [xs as *const _, ptr::null()];
    let df = dataframe_new(ptrs.as_ptr(), ptrs.len());
    assert!(df.is_null());
    series_drop(xs);
}

#[test]
fn dataframe_new_mismatched_lengths_returns_null() {
    // Two columns of unequal length is a Polars error and must
    // surface as a null pointer, not a panic.
    let xs = make_i32("x", &[1, 2, 3]);
    let ys = make_i32("y", &[10, 20]);
    let ptrs: [*const Series; 2] = [xs as *const _, ys as *const _];
    let df = dataframe_new(ptrs.as_ptr(), ptrs.len());
    assert!(df.is_null());
    series_drop(xs);
    series_drop(ys);
}

#[test]
fn dataframe_new_empty_array_is_ok() {
    let df = dataframe_new(ptr::null(), 0);
    assert!(!df.is_null());
    assert_eq!(dataframe_height(df), 0);
    assert_eq!(dataframe_width(df), 0);
    dataframe_drop(df);
}

// --- shape / metadata on null pointer ----------------------------

#[test]
fn height_and_width_on_null_df_return_zero() {
    assert_eq!(dataframe_height(ptr::null_mut()), 0);
    assert_eq!(dataframe_width(ptr::null_mut()), 0);
}

#[test]
fn shape_on_null_df_returns_zero_zero() {
    let sh = dataframe_shape(ptr::null_mut());
    assert_eq!(sh.rows, 0);
    assert_eq!(sh.cols, 0);
}

// --- column access -----------------------------------------------

#[test]
fn column_name_returns_each_name() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    assert_eq!(read_column_names(df), vec!["x", "g"]);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn column_name_out_of_range_returns_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    assert!(dataframe_column_name(df, 99).is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn column_returns_cloned_series_by_name() {
    let (df, xs, gs) = make_xg(&[10, 20, 30], &["a", "b", "c"]);
    let n = cstr("x");
    let col = dataframe_column(df, n.as_ptr());
    assert!(!col.is_null());
    assert_eq!(series_len(col), 3);
    assert_eq!(series_ref_i32(col, 1).value, 20);
    // The returned series is independent: dropping it leaves df
    // intact.
    series_drop(col);
    assert_eq!(dataframe_height(df), 3);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn column_unknown_name_returns_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    let n = cstr("nope");
    assert!(dataframe_column(df, n.as_ptr()).is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn column_null_inputs_return_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    assert!(dataframe_column(df, ptr::null()).is_null());
    assert!(dataframe_column(ptr::null_mut(), cstr("x").as_ptr()).is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

// --- row-shaping -------------------------------------------------

#[test]
fn head_returns_first_n_rows() {
    let (df, xs, gs) = make_xg(&[1, 2, 3, 4, 5], &["a", "b", "c", "d", "e"]);
    let h = dataframe_head(df, 2);
    assert_eq!(dataframe_height(h), 2);
    assert_eq!(read_i32_col(h, "x"), vec![1, 2]);
    dataframe_drop(h);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn tail_returns_last_n_rows() {
    let (df, xs, gs) = make_xg(&[1, 2, 3, 4, 5], &["a", "b", "c", "d", "e"]);
    let t = dataframe_tail(df, 2);
    assert_eq!(dataframe_height(t), 2);
    assert_eq!(read_i32_col(t, "x"), vec![4, 5]);
    dataframe_drop(t);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn slice_offset_length_picks_window() {
    let (df, xs, gs) =
        make_xg(&[10, 20, 30, 40, 50], &["a", "b", "c", "d", "e"]);
    let sl = dataframe_slice(df, 1, 3);
    assert_eq!(dataframe_height(sl), 3);
    assert_eq!(read_i32_col(sl, "x"), vec![20, 30, 40]);
    dataframe_drop(sl);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn row_shaping_on_null_df_returns_null() {
    assert!(dataframe_head(ptr::null_mut(), 1).is_null());
    assert!(dataframe_tail(ptr::null_mut(), 1).is_null());
    assert!(dataframe_slice(ptr::null_mut(), 0, 1).is_null());
}

// --- column ops --------------------------------------------------

#[test]
fn select_returns_named_columns_in_order() {
    let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
    let g_name = cstr("g");
    let x_name = cstr("x");
    let names: [*const c_char; 2] = [g_name.as_ptr(), x_name.as_ptr()];
    let out = dataframe_select(df, names.as_ptr(), names.len());
    assert!(!out.is_null());
    assert_eq!(read_column_names(out), vec!["g", "x"]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn select_unknown_name_returns_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    let n = cstr("nope");
    let names: [*const c_char; 1] = [n.as_ptr()];
    let out = dataframe_select(df, names.as_ptr(), names.len());
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn drop_columns_removes_named() {
    let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
    let g_name = cstr("g");
    let names: [*const c_char; 1] = [g_name.as_ptr()];
    let out = dataframe_drop_columns(df, names.as_ptr(), names.len());
    assert!(!out.is_null());
    assert_eq!(read_column_names(out), vec!["x"]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn drop_columns_unknown_returns_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    let n = cstr("nope");
    let names: [*const c_char; 1] = [n.as_ptr()];
    let out = dataframe_drop_columns(df, names.as_ptr(), names.len());
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn rename_changes_column_name() {
    let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
    let old = cstr("g");
    let new = cstr("group");
    let out = dataframe_rename(df, old.as_ptr(), new.as_ptr());
    assert!(!out.is_null());
    assert_eq!(read_column_names(out), vec!["x", "group"]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn rename_unknown_column_returns_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    let old = cstr("nope");
    let new = cstr("group");
    let out = dataframe_rename(df, old.as_ptr(), new.as_ptr());
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn with_column_appends_new_column() {
    let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
    let extra = make_i32("y", &[100, 200]);
    let out = dataframe_with_column(df, extra);
    assert!(!out.is_null());
    assert_eq!(read_column_names(out), vec!["x", "g", "y"]);
    assert_eq!(read_i32_col(out, "y"), vec![100, 200]);
    dataframe_drop(out);
    series_drop(extra);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn with_column_replaces_existing_column_in_place() {
    // A column named "x" already exists; `with_column` should
    // replace it rather than appending a duplicate.
    let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
    let replacement = make_i32("x", &[42, 84]);
    let out = dataframe_with_column(df, replacement);
    assert!(!out.is_null());
    assert_eq!(dataframe_width(out), 2);
    assert_eq!(read_column_names(out), vec!["x", "g"]);
    assert_eq!(read_i32_col(out, "x"), vec![42, 84]);
    dataframe_drop(out);
    series_drop(replacement);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

// --- filter / sort -----------------------------------------------

#[test]
fn filter_with_bool_mask_keeps_true_rows() {
    let (df, xs, gs) = make_xg(&[1, 2, 3, 4], &["a", "b", "c", "d"]);
    // Mask = x > 2: keep rows 3 and 4.
    let mask = series_gt_i32(xs, 2);
    let out = dataframe_filter(df, mask);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 2);
    assert_eq!(read_i32_col(out, "x"), vec![3, 4]);
    dataframe_drop(out);
    series_drop(mask);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn filter_null_mask_returns_null() {
    let (df, xs, gs) = make_xg(&[1], &["a"]);
    assert!(dataframe_filter(df, ptr::null_mut()).is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn filter_non_bool_mask_returns_null() {
    // Passing an i32 series as the mask is a polars type error
    // that the wrapper must surface as a null pointer.
    let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
    assert!(dataframe_filter(df, xs).is_null());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn sort_ascending_and_descending() {
    let (df, xs, gs) = make_xg(&[3, 1, 2], &["a", "b", "c"]);
    let by = cstr("x");
    let by_arr: [*const c_char; 1] = [by.as_ptr()];

    let asc = dataframe_sort(df, by_arr.as_ptr(), ptr::null(), by_arr.len());
    assert!(!asc.is_null());
    assert_eq!(read_i32_col(asc, "x"), vec![1, 2, 3]);
    dataframe_drop(asc);

    let desc_flag: [u8; 1] = [1];
    let desc =
        dataframe_sort(df, by_arr.as_ptr(), desc_flag.as_ptr(), by_arr.len());
    assert!(!desc.is_null());
    assert_eq!(read_i32_col(desc, "x"), vec![3, 2, 1]);
    dataframe_drop(desc);

    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn sort_two_keys_with_descending_flags() {
    // Sort by g ascending, then x descending: groups of g come
    // out in 'a','b' order; within each group x is reversed.
    let g_a = cstr("g");
    let x_n = cstr("x");
    let by_arr: [*const c_char; 2] = [g_a.as_ptr(), x_n.as_ptr()];
    let desc_flags: [u8; 2] = [0, 1];

    let (df, xs, gs) = make_xg(&[1, 2, 3, 4], &["b", "a", "b", "a"]);
    let out =
        dataframe_sort(df, by_arr.as_ptr(), desc_flags.as_ptr(), by_arr.len());
    assert!(!out.is_null());
    // After sort: g = a a b b, x = 4 2 3 1.
    assert_eq!(read_i32_col(out, "x"), vec![4, 2, 3, 1]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn sort_null_df_returns_null() {
    let by = cstr("x");
    let by_arr: [*const c_char; 1] = [by.as_ptr()];
    assert!(dataframe_sort(
        ptr::null_mut(),
        by_arr.as_ptr(),
        ptr::null(),
        by_arr.len()
    )
    .is_null());
}

// --- unique / drop_nulls -----------------------------------------

#[test]
fn unique_dedupes_rows() {
    let xs = make_i32("x", &[1, 1, 2, 2, 3]);
    let gs = make_str("g", &["a", "a", "b", "b", "c"]);
    let df = make_df(&[xs, gs]);
    let out = dataframe_unique(df);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 3);
    // Polars doesn't guarantee row order after `.unique()` — pull
    // x column, sort, and check the set of survivors.
    let mut got = read_i32_col(out, "x");
    got.sort();
    assert_eq!(got, vec![1, 2, 3]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn drop_nulls_removes_rows_with_any_null() {
    let xs = make_opt_i32("x", &[Some(1), None, Some(3), Some(4)]);
    let gs = make_str("g", &["a", "b", "c", "d"]);
    let df = make_df(&[xs, gs]);
    let out = dataframe_drop_nulls(df);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 3);
    assert_eq!(read_i32_col(out, "x"), vec![1, 3, 4]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn unique_and_drop_nulls_null_df_return_null() {
    assert!(dataframe_unique(ptr::null_mut()).is_null());
    assert!(dataframe_drop_nulls(ptr::null_mut()).is_null());
}
