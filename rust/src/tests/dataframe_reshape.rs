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
    let on = cstr("type");
    let on_arr: [*const c_char; 1] = [on.as_ptr()];
    let idx = cstr("id");
    let idx_arr: [*const c_char; 1] = [idx.as_ptr()];
    let val = cstr("value");
    let val_arr: [*const c_char; 1] = [val.as_ptr()];
    let out = dataframe_pivot(
        df,
        on_arr.as_ptr(),
        on_arr.len(),
        idx_arr.as_ptr(),
        idx_arr.len(),
        val_arr.as_ptr(),
        val_arr.len(),
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
    let on = cstr("type");
    let on_arr: [*const c_char; 1] = [on.as_ptr()];
    let idx = cstr("id");
    let idx_arr: [*const c_char; 1] = [idx.as_ptr()];
    let val = cstr("value");
    let val_arr: [*const c_char; 1] = [val.as_ptr()];
    let out = dataframe_pivot(
        df,
        on_arr.as_ptr(),
        on_arr.len(),
        idx_arr.as_ptr(),
        idx_arr.len(),
        val_arr.as_ptr(),
        val_arr.len(),
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
    let a_n = cstr("a");
    let b_n = cstr("b");
    let on: [*const c_char; 2] = [a_n.as_ptr(), b_n.as_ptr()];
    let id_n = cstr("id");
    let idx: [*const c_char; 1] = [id_n.as_ptr()];
    let out =
        dataframe_unpivot(df, on.as_ptr(), on.len(), idx.as_ptr(), idx.len());
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
fn unpivot_unknown_column_returns_null() {
    let (df, id, ty, v) = make_long();
    let bad = cstr("nope");
    let on: [*const c_char; 1] = [bad.as_ptr()];
    let id_n = cstr("id");
    let idx: [*const c_char; 1] = [id_n.as_ptr()];
    let out =
        dataframe_unpivot(df, on.as_ptr(), on.len(), idx.as_ptr(), idx.len());
    assert!(out.is_null());
    dataframe_drop(df);
    series_drop(id);
    series_drop(ty);
    series_drop(v);
}
