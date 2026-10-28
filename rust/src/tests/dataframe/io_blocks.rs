use super::io::{write_csv, write_parquet};
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

fn read_csv_with(
    path: *const c_char,
    prefix: StrArg,
    nulls: StrListArg,
    new_columns: StrListArg,
) -> bool {
    dataframe_read_csv_v3(
        path,
        CompatCsvOptions::default(),
        prefix,
        ptr::null(),
        nulls,
        ptr::null(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
        0,
        new_columns,
        ptr::null(),
        ptr::null(),
        0,
    )
    .is_null()
}

#[test]
fn every_io_v2_refuses_a_malformed_block_with_its_cause() {
    let bad: Vec<u64> = vec![2, 1];
    let bad_list: Vec<u64> = vec![3, 1, 0];
    let (bad, bad_list) = (bad.as_ptr(), bad_list.as_ptr());
    let dir = tempfile::tempdir().expect("tempdir");
    let at = |name: &str| cstr(dir.path().join(name).to_str().unwrap());
    let (csv, parquet, json, ndjson, written) = (
        at("x.csv"),
        at("x.parquet"),
        at("x.json"),
        at("x.ndjson"),
        at("w.csv"),
    );
    let xs = make_i64("x", &[1, 2]);
    let df = make_df(&[xs]);
    assert_eq!(write_csv(df, csv.as_ptr()), 0);
    assert_eq!(write_parquet(df, parquet.as_ptr()), 0);
    assert_eq!(dataframe_write_json(df, json.as_ptr()), 0);
    assert_eq!(
        dataframe_write_ndjson_with_options(
            df,
            ndjson.as_ptr(),
            0,
            false,
            0,
            true
        ),
        0
    );
    let int64 = dtype(CompatDTypeTag::Int64);
    let rows: Vec<(&str, Box<dyn Fn() -> bool + '_>)> = vec![
        (
            "dataframe_read_csv_v3",
            Box::new(|| {
                read_csv_with(csv.as_ptr(), bad, ptr::null(), ptr::null())
                    && read_csv_with(
                        csv.as_ptr(),
                        ptr::null(),
                        bad_list,
                        ptr::null(),
                    )
            }),
        ),
        (
            "lazyframe_scan_csv_v3",
            Box::new(|| {
                lazyframe_scan_csv_v3(
                    csv.as_ptr(),
                    CompatCsvOptions::default(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    0,
                    bad_list,
                    ptr::null(),
                    ptr::null(),
                    0,
                )
                .is_null()
            }),
        ),
        (
            "dataframe_write_csv_with_options_v2",
            Box::new(|| {
                dataframe_write_csv_with_options_v2(
                    df,
                    written.as_ptr(),
                    CompatCsvWriteOptions::default(),
                    ptr::null(),
                    bad,
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                ) != 0
            }),
        ),
        (
            "dataframe_read_json_with_options_v2",
            Box::new(|| {
                dataframe_read_json_with_options_v2(
                    json.as_ptr(),
                    CompatJsonOptions {
                        overrides_len: 1,
                        ..Default::default()
                    },
                    ptr::null(),
                    ptr::null(),
                    bad_list,
                    &int64,
                )
                .is_null()
            }),
        ),
        (
            "dataframe_read_ndjson_with_options_v2",
            Box::new(|| {
                dataframe_read_ndjson_with_options_v2(
                    ndjson.as_ptr(),
                    CompatNdjsonOptions {
                        overrides_len: 1,
                        ..Default::default()
                    },
                    ptr::null(),
                    ptr::null(),
                    bad_list,
                    &int64,
                    ptr::null(),
                    ptr::null(),
                )
                .is_null()
            }),
        ),
        (
            "lazyframe_scan_ndjson_with_options_v2",
            Box::new(|| {
                lazyframe_scan_ndjson_with_options_v2(
                    ndjson.as_ptr(),
                    CompatNdjsonOptions::default(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    ptr::null(),
                    bad,
                    ptr::null(),
                )
                .is_null()
            }),
        ),
        (
            "dataframe_read_parquet_with_options_v2",
            Box::new(|| {
                dataframe_read_parquet_with_options_v2(
                    parquet.as_ptr(),
                    CompatParquetReadOptions::default(),
                    ptr::null(),
                    ptr::null(),
                    1,
                    bad_list,
                    ptr::null(),
                    1,
                )
                .is_null()
            }),
        ),
        (
            "lazyframe_scan_parquet_with_options_v2",
            Box::new(|| {
                lazyframe_scan_parquet_with_options_v2(
                    parquet.as_ptr(),
                    CompatParquetReadOptions::default(),
                    ptr::null(),
                    bad,
                )
                .is_null()
            }),
        ),
    ];
    for (name, call) in rows {
        assert!(call(), "{name} accepted a malformed block");
        assert_eq!(
            recorded_error(),
            Some(StrError::Truncated.to_string()),
            "{name}"
        );
    }
    assert!(!dir.path().join("w.csv").exists());
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn the_io_v2s_refuse_lists_whose_counts_disagree() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("x.csv");
    std::fs::write(&path, b"x\n1\n").expect("write");
    let p = cstr(path.to_str().unwrap());
    let (one, two) = (str_list_block(&["x"]), str_list_block(&["x", "y"]));
    let float64 = dtype(CompatDTypeTag::Float64);
    let read = |columns: StrListArg, markers: StrListArg, names: StrListArg| {
        let out = dataframe_read_csv_v3(
            p.as_ptr(),
            CompatCsvOptions::default(),
            ptr::null(),
            ptr::null(),
            ptr::null(),
            columns,
            markers,
            names,
            &float64,
            1,
            ptr::null(),
            ptr::null(),
            ptr::null(),
            0,
        );
        assert!(out.is_null());
        recorded_error().expect("a reason")
    };
    assert_eq!(
        read(one.as_ptr(), two.as_ptr(), one.as_ptr()),
        "1 null value columns are given for 2 null values"
    );
    assert_eq!(
        read(ptr::null(), ptr::null(), two.as_ptr()),
        "2 override names are given for 1 dtypes"
    );
    let parquet = dir.path().join("x.parquet");
    let q = cstr(parquet.to_str().unwrap());
    let xs = make_i64("x", &[1]);
    let df = make_df(&[xs]);
    assert_eq!(write_parquet(df, q.as_ptr()), 0);
    let selected = dataframe_read_parquet_with_options_v2(
        q.as_ptr(),
        CompatParquetReadOptions::default(),
        ptr::null(),
        ptr::null(),
        1,
        two.as_ptr(),
        ptr::null(),
        1,
    );
    assert!(selected.is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("2 column names are given for 1 columns")
    );
    let json = dir.path().join("x.json");
    let j = cstr(json.to_str().unwrap());
    assert_eq!(dataframe_write_json(df, j.as_ptr()), 0);
    let read_json = dataframe_read_json_with_options_v2(
        j.as_ptr(),
        CompatJsonOptions {
            overrides_len: 1,
            ..Default::default()
        },
        ptr::null(),
        ptr::null(),
        two.as_ptr(),
        &float64,
    );
    assert!(read_json.is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("2 override names are given for 1 dtypes")
    );
    dataframe_drop(df);
    series_drop(xs);
}
