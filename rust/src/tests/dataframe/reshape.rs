use super::test_util::*;
use super::*;

/// Long-form table: id ∈ {1,2}, type ∈ {"x","y"}, value ∈ ints.
fn make_long() -> (*mut DataFrame, *mut Series, *mut Series, *mut Series) {
    let id = make_i32("id", &[1, 1, 2, 2]);
    let ty = make_str("type", &["x", "y", "x", "y"]);
    let v = make_i32("value", &[10, 11, 20, 21]);
    let df = make_df(&[id, ty, v]);
    (df, id, ty, v)
}

#[test]
fn pivot_with_first_agg() {
    let (df, id, ty, v) = make_long();
    let on_arr = str_list_block(&["type"]);
    let idx_arr = str_list_block(&["id"]);
    let val_arr = str_list_block(&["value"]);
    let out = dataframe_pivot_v2(
        df,
        on_arr.as_ptr(),
        idx_arr.as_ptr(),
        val_arr.as_ptr(),
        CompatPivotAgg::First as i32,
    );
    assert!(!out.is_null());
    // 2 unique ids x (id col + x col + y col) = 2 rows, 3 cols.
    assert_eq!(dataframe_height(out), 2);
    assert_eq!(dataframe_width(out), 3);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(id);
    series_drop(ty);
    series_drop(v);
}

#[test]
fn pivot_unknown_agg_returns_null() {
    let (df, id, ty, v) = make_long();
    let on_arr = str_list_block(&["type"]);
    let idx_arr = str_list_block(&["id"]);
    let val_arr = str_list_block(&["value"]);
    let out = dataframe_pivot_v2(
        df,
        on_arr.as_ptr(),
        idx_arr.as_ptr(),
        val_arr.as_ptr(),
        999,
    );
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(id);
    series_drop(ty);
    series_drop(v);
}

#[test]
fn unpivot_melts_wide_to_long() {
    // Wide-form: id + a + b.
    let id = make_i32("id", &[1, 2]);
    let a = make_i32("a", &[10, 20]);
    let b = make_i32("b", &[100, 200]);
    let df = make_df(&[id, a, b]);
    let on = str_list_block(&["a", "b"]);
    let idx = str_list_block(&["id"]);
    let out = dataframe_unpivot_v2(df, on.as_ptr(), idx.as_ptr());
    assert!(!out.is_null());
    // 2 ids * 2 value columns -> 4 rows.
    assert_eq!(dataframe_height(out), 4);
    // Columns: id + "variable" + "value".
    assert_eq!(read_column_names(out), vec!["id", "variable", "value"]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(id);
    series_drop(a);
    series_drop(b);
}

#[test]
fn unpivot_with_no_on_melts_every_non_index_column() {
    let id = make_i32("id", &[1, 2]);
    let a = make_i32("a", &[10, 20]);
    let b = make_i32("b", &[100, 200]);
    let df = make_df(&[id, a, b]);
    let idx = str_list_block(&["id"]);
    let out = dataframe_unpivot_v2(df, ptr::null(), idx.as_ptr());
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 4);
    assert_eq!(read_column_names(out), vec!["id", "variable", "value"]);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(id);
    series_drop(a);
    series_drop(b);
}

#[test]
fn unpivot_unknown_column_returns_null() {
    let (df, id, ty, v) = make_long();
    let on = str_list_block(&["nope"]);
    let idx = str_list_block(&["id"]);
    let out = dataframe_unpivot_v2(df, on.as_ptr(), idx.as_ptr());
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(id);
    series_drop(ty);
    series_drop(v);
}
