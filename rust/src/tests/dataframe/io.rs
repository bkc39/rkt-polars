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

// --- failure reporting (#45) ---------------------------------------------
//
// Every entry point below clears the error slot on the way in, so each test
// asserts on a message its own call recorded rather than a leftover.

/// Read back and free the recorded message, or `None` when nothing was
/// recorded.
fn recorded_error() -> Option<String> {
    let p = last_error_message();
    if p.is_null() {
        None
    } else {
        Some(take_cstring(p))
    }
}

#[test]
fn missing_file_reports_the_os_reason() {
    let dir = tempfile::tempdir().expect("tempdir");
    let p = cstr(dir.path().join("nope.csv").to_str().unwrap());
    assert!(dataframe_read_csv(p.as_ptr()).is_null());
    let msg = recorded_error().expect("a reason should have been recorded");
    assert!(
        msg.contains("cannot open file"),
        "expected the failing step, got {:?}",
        msg
    );
    assert!(
        msg.to_lowercase().contains("no such file"),
        "expected the OS reason, got {:?}",
        msg
    );
}

#[test]
fn unwritable_path_reports_the_os_reason() {
    let p = cstr("/nonexistent-directory-45/out.parquet");
    let xs = make_i32("x", &[1]);
    let df = make_df(&[xs]);
    assert_ne!(dataframe_write_parquet(df, p.as_ptr()), 0);
    let msg = recorded_error().expect("a reason should have been recorded");
    assert!(
        msg.contains("cannot create file"),
        "expected the failing step, got {:?}",
        msg
    );
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn malformed_input_reports_the_polars_reason() {
    // A parquet reader pointed at a text file fails inside polars rather than
    // at open time, so this exercises the reader arm rather than the OS arm.
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("not-really.parquet");
    std::fs::write(&path, b"this is not parquet").expect("write");
    let p = cstr(path.to_str().unwrap());
    assert!(dataframe_read_parquet(p.as_ptr()).is_null());
    let msg = recorded_error().expect("a reason should have been recorded");
    assert!(
        msg.contains("parquet reader"),
        "expected the failing component, got {:?}",
        msg
    );
    assert!(
        msg.len() > "parquet reader: ".len(),
        "expected polars' own text after the component, got {:?}",
        msg
    );
}

#[test]
fn null_arguments_say_which_one() {
    let xs = make_i32("x", &[1]);
    let df = make_df(&[xs]);

    assert_eq!(
        dataframe_write_csv(ptr::null_mut(), cstr("/tmp/x").as_ptr()),
        1
    );
    assert_eq!(recorded_error().as_deref(), Some("dataframe is null"));

    assert_eq!(dataframe_write_csv(df, ptr::null()), 1);
    assert_eq!(recorded_error().as_deref(), Some("path is null"));

    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn success_leaves_no_message_behind() {
    // A failure followed by a success must not leave the old reason readable,
    // or the next caller would attribute it to the wrong call.
    let dir = tempfile::tempdir().expect("tempdir");
    let missing = cstr(dir.path().join("nope.csv").to_str().unwrap());
    assert!(dataframe_read_csv(missing.as_ptr()).is_null());
    assert!(recorded_error().is_some());

    let xs = make_i32("x", &[1, 2]);
    let df = make_df(&[xs]);
    let out = cstr(dir.path().join("ok.csv").to_str().unwrap());
    assert_eq!(dataframe_write_csv(df, out.as_ptr()), 0);
    assert_eq!(
        recorded_error(),
        None,
        "a successful call must clear the slot"
    );

    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn a_broken_lazy_pipeline_reports_a_reason() {
    // A lazy scan only builds a plan, so a missing or malformed file may be
    // accepted here and rejected at collect time instead. Either is fine; what
    // must hold is that whichever step fails records a reason rather than
    // handing back a bare null.
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("not-really.parquet");
    std::fs::write(&path, b"this is not parquet").expect("write");
    let p = cstr(path.to_str().unwrap());

    let lf = lazyframe_scan_parquet(p.as_ptr());
    if lf.is_null() {
        let msg =
            recorded_error().expect("scan failure should record a reason");
        assert!(
            msg.contains("parquet scan"),
            "expected the failing component, got {:?}",
            msg
        );
        return;
    }

    let df = lazyframe_collect(lf);
    assert!(df.is_null(), "collecting a malformed parquet should fail");
    let msg = recorded_error().expect("collect failure should record a reason");
    assert!(
        msg.to_lowercase().contains("parquet"),
        "expected polars' own text about the bad file, got {:?}",
        msg
    );
    lazyframe_drop(lf);
}

#[test]
fn collect_of_a_null_lazyframe_reports_a_reason() {
    assert!(lazyframe_collect(ptr::null_mut()).is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("collect: lazyframe is null")
    );
}
