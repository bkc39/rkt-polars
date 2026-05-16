use super::test_util::*;
use super::*;

fn write_round_trip(
    df: *mut DataFrame,
    ext: &str,
    writer: extern "C" fn(*mut DataFrame, *const c_char) -> i32,
    reader: extern "C" fn(*const c_char) -> *mut DataFrame,
) -> *mut DataFrame {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join(format!("out.{}", ext));
    let p_owned = cstr(path.to_str().unwrap());
    let rc = writer(df, p_owned.as_ptr());
    assert_eq!(rc, 0, "writer returned non-zero status");
    let back = reader(p_owned.as_ptr());
    assert!(!back.is_null(), "reader returned null");
    back
}

// Use i64 input throughout: CSV / JSON-Lines readers infer
// integer columns as i64, and Parquet preserves the i64 schema —
// so all three round-trip back to i64 uniformly.

#[test]
fn csv_round_trip_preserves_shape_and_values() {
    let xs = make_i64("x", &[1, 2, 3]);
    let gs = make_str("g", &["a", "b", "c"]);
    let df = make_df(&[xs, gs]);
    let back =
        write_round_trip(df, "csv", dataframe_write_csv, dataframe_read_csv);
    assert_eq!(dataframe_height(back), 3);
    assert_eq!(read_column_names(back), vec!["x", "g"]);
    assert_eq!(read_i64_col(back, "x"), vec![1, 2, 3]);
    assert_eq!(
        read_str_col(back, "g"),
        vec!["a".to_string(), "b".to_string(), "c".to_string()]
    );
    dataframe_drop(back);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn parquet_round_trip_preserves_shape_and_values() {
    let xs = make_i64("x", &[1, 2, 3]);
    let gs = make_str("g", &["a", "b", "c"]);
    let df = make_df(&[xs, gs]);
    let back = write_round_trip(
        df,
        "parquet",
        dataframe_write_parquet,
        dataframe_read_parquet,
    );
    assert_eq!(dataframe_height(back), 3);
    assert_eq!(read_i64_col(back, "x"), vec![1, 2, 3]);
    dataframe_drop(back);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn json_lines_round_trip_preserves_shape_and_values() {
    let xs = make_i64("x", &[1, 2, 3]);
    let gs = make_str("g", &["a", "b", "c"]);
    let df = make_df(&[xs, gs]);
    let back = write_round_trip(
        df,
        "jsonl",
        dataframe_write_json_lines,
        dataframe_read_json_lines,
    );
    assert_eq!(dataframe_height(back), 3);
    assert_eq!(read_i64_col(back, "x"), vec![1, 2, 3]);
    dataframe_drop(back);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn read_csv_missing_path_returns_null() {
    let dir = tempfile::tempdir().expect("tempdir");
    let p = dir.path().join("nope.csv");
    let p_owned = cstr(p.to_str().unwrap());
    assert!(dataframe_read_csv(p_owned.as_ptr()).is_null());
}

#[test]
fn write_csv_status_codes_null_inputs() {
    // write returns 1 for null df / null path, not 0 (success).
    let xs = make_i32("x", &[1]);
    let df = make_df(&[xs]);
    assert_eq!(
        dataframe_write_csv(ptr::null_mut(), cstr("/tmp/x").as_ptr()),
        1
    );
    assert_eq!(dataframe_write_csv(df, ptr::null()), 1);
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn to_string_returns_non_null_cstring() {
    let xs = make_i32("x", &[1, 2]);
    let df = make_df(&[xs]);
    let s = dataframe_to_string(df);
    assert!(!s.is_null());
    let formatted = take_cstring(s);
    assert!(
        formatted.contains("x"),
        "to_string output missing column header: {:?}",
        formatted
    );
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn to_string_null_df_returns_null() {
    assert!(dataframe_to_string(ptr::null_mut()).is_null());
}
