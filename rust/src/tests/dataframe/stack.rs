use super::test_util::*;
use super::*;

#[test]
fn vstack_appends_rows() {
    let a_x = make_i32("x", &[1, 2]);
    let a_g = make_str("g", &["a", "b"]);
    let a = make_df(&[a_x, a_g]);
    let b_x = make_i32("x", &[3, 4]);
    let b_g = make_str("g", &["c", "d"]);
    let b = make_df(&[b_x, b_g]);
    let out = dataframe_vstack(a, b);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 4);
    assert_eq!(read_i32_col(out, "x"), vec![1, 2, 3, 4]);
    dataframe_drop(out);
    dataframe_drop(a);
    dataframe_drop(b);
    for s in [a_x, a_g, b_x, b_g] {
        series_drop(s);
    }
}

#[test]
fn vstack_schema_mismatch_returns_null() {
    // Different column types between a and b -> polars rejects.
    let a_x = make_i32("x", &[1]);
    let a = make_df(&[a_x]);
    let b_x = make_f64("x", &[1.0]);
    let b = make_df(&[b_x]);
    assert!(dataframe_vstack(a, b).is_null());
    dataframe_drop(a);
    dataframe_drop(b);
    series_drop(a_x);
    series_drop(b_x);
}

#[test]
fn vstack_null_inputs_return_null() {
    let a_x = make_i32("x", &[1]);
    let a = make_df(&[a_x]);
    assert!(dataframe_vstack(ptr::null_mut(), a).is_null());
    assert!(dataframe_vstack(a, ptr::null_mut()).is_null());
    dataframe_drop(a);
    series_drop(a_x);
}

#[test]
fn hstack_appends_columns() {
    let a_x = make_i32("x", &[1, 2, 3]);
    let a = make_df(&[a_x]);
    let extra1 = make_i32("y", &[10, 20, 30]);
    let extra2 = make_str("g", &["a", "b", "c"]);
    let ptrs: [*const Series; 2] = [extra1 as *const _, extra2 as *const _];
    let out = dataframe_hstack(a, ptrs.as_ptr(), ptrs.len());
    assert!(!out.is_null());
    assert_eq!(dataframe_width(out), 3);
    assert_eq!(read_column_names(out), vec!["x", "y", "g"]);
    assert_eq!(read_i32_col(out, "y"), vec![10, 20, 30]);
    dataframe_drop(out);
    dataframe_drop(a);
    series_drop(a_x);
    series_drop(extra1);
    series_drop(extra2);
}

#[test]
fn hstack_null_inputs_return_null() {
    assert!(dataframe_hstack(ptr::null_mut(), ptr::null(), 0).is_null());
    let a_x = make_i32("x", &[1]);
    let a = make_df(&[a_x]);
    // null Series in the array
    let ptrs: [*const Series; 1] = [ptr::null()];
    assert!(dataframe_hstack(a, ptrs.as_ptr(), ptrs.len()).is_null());
    dataframe_drop(a);
    series_drop(a_x);
}
