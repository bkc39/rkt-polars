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

#[test]
fn missing_file_reports_the_os_reason() {
    let dir = tempfile::tempdir().expect("tempdir");
    let p = cstr(dir.path().join("nope.csv").to_str().unwrap());
    assert!(dataframe_read_csv(p.as_ptr()).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(msg.starts_with("cannot open file: "), "{:?}", msg);
    assert!(msg.to_lowercase().contains("no such file"), "{:?}", msg);
}

#[test]
fn unwritable_path_reports_the_os_reason() {
    let xs = make_i32("x", &[1]);
    let df = make_df(&[xs]);
    let p = cstr("/nonexistent-directory-45/out.parquet");
    assert_eq!(dataframe_write_parquet(df, p.as_ptr()), 3);
    let msg = recorded_error().expect("a reason");
    assert!(msg.starts_with("cannot create file: "), "{:?}", msg);
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn malformed_input_reports_the_polars_reason() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("junk.bin");
    std::fs::write(&path, b"this is not parquet").expect("write");
    let p = cstr(path.to_str().unwrap());
    assert!(dataframe_read_parquet(p.as_ptr()).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(msg.contains("PAR1"), "{:?}", msg);
}

#[test]
fn null_arguments_say_which_one() {
    let xs = make_i32("x", &[1]);
    let df = make_df(&[xs]);
    let p = cstr("/tmp/x");
    assert_eq!(dataframe_write_csv(ptr::null_mut(), p.as_ptr()), 1);
    assert_eq!(recorded_error().as_deref(), Some("dataframe is null"));
    assert_eq!(dataframe_write_csv(df, ptr::null()), 1);
    assert_eq!(recorded_error().as_deref(), Some("path is null"));
    assert!(dataframe_read_csv(ptr::null()).is_null());
    assert_eq!(recorded_error().as_deref(), Some("path is null"));
    assert!(lazyframe_collect(ptr::null_mut()).is_null());
    assert_eq!(recorded_error().as_deref(), Some("lazyframe is null"));
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn every_entry_point_clears_a_stale_reason() {
    let dir = tempfile::tempdir().expect("tempdir");
    let at = |name: &str| cstr(dir.path().join(name).to_str().unwrap());
    let (csv, parquet, ndjson) = (at("f.csv"), at("f.parquet"), at("f.ndjson"));
    let xs = make_i64("x", &[1, 2, 3]);
    let df = make_df(&[xs]);

    let cleared = |label: &str| {
        assert_eq!(recorded_error(), None, "{} left a stale reason", label);
        set_last_error("stale");
    };
    let frame = |label: &str, out: *mut DataFrame| {
        assert!(!out.is_null(), "{} failed", label);
        dataframe_drop(out);
    };
    let plan = |label: &str, out: *mut LazyFrame| {
        assert!(!out.is_null(), "{} failed", label);
        lazyframe_drop(out);
    };

    set_last_error("stale");
    assert_eq!(dataframe_write_csv(df, csv.as_ptr()), 0);
    cleared("dataframe_write_csv");
    assert_eq!(dataframe_write_parquet(df, parquet.as_ptr()), 0);
    cleared("dataframe_write_parquet");
    assert_eq!(dataframe_write_json_lines(df, ndjson.as_ptr()), 0);
    cleared("dataframe_write_json_lines");
    frame("dataframe_read_csv", dataframe_read_csv(csv.as_ptr()));
    cleared("dataframe_read_csv");
    frame(
        "dataframe_read_parquet",
        dataframe_read_parquet(parquet.as_ptr()),
    );
    cleared("dataframe_read_parquet");
    frame(
        "dataframe_read_json_lines",
        dataframe_read_json_lines(ndjson.as_ptr()),
    );
    cleared("dataframe_read_json_lines");
    plan("lazyframe_scan_csv", lazyframe_scan_csv(csv.as_ptr()));
    cleared("lazyframe_scan_csv");
    plan(
        "lazyframe_scan_csv_options",
        lazyframe_scan_csv_options(csv.as_ptr(), 1, b',', 0, 0, 0),
    );
    cleared("lazyframe_scan_csv_options");
    plan(
        "lazyframe_scan_parquet",
        lazyframe_scan_parquet(parquet.as_ptr()),
    );
    cleared("lazyframe_scan_parquet");
    plan(
        "lazyframe_scan_parquet_options",
        lazyframe_scan_parquet_options(parquet.as_ptr(), 0, 0),
    );
    cleared("lazyframe_scan_parquet_options");
    let lf = lazyframe_scan_csv(csv.as_ptr());
    set_last_error("stale");
    frame("lazyframe_collect", lazyframe_collect(lf));
    cleared("lazyframe_collect");

    lazyframe_drop(lf);
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn a_scan_defers_a_bad_file_to_collect() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("junk.bin");
    std::fs::write(&path, b"this is not parquet").expect("write");
    let p = cstr(path.to_str().unwrap());

    let lf = lazyframe_scan_parquet(p.as_ptr());
    assert!(!lf.is_null(), "the scan itself should only build a plan");
    assert_eq!(recorded_error(), None);

    assert!(lazyframe_collect(lf).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(msg.contains("PAR1"), "{:?}", msg);
    lazyframe_drop(lf);
}

#[test]
fn an_invalid_glob_fails_at_collect() {
    let p = cstr("/tmp/[.csv");
    let lf = lazyframe_scan_csv(p.as_ptr());
    assert!(!lf.is_null(), "the scan itself should only build a plan");
    assert!(lazyframe_collect(lf).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(msg.to_lowercase().contains("glob"), "{:?}", msg);
    lazyframe_drop(lf);
}
