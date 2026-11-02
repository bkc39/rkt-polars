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

#[derive(Clone, Copy)]
struct CsvBlocks {
    comment_prefix: StrArg,
    null_values: StrListArg,
    null_columns: StrListArg,
    null_markers: StrListArg,
    override_names: StrListArg,
    override_dtypes: *const CompatDType,
    overrides_len: usize,
    new_columns: StrListArg,
}

impl Default for CsvBlocks {
    fn default() -> Self {
        CsvBlocks {
            comment_prefix: ptr::null(),
            null_values: ptr::null(),
            null_columns: ptr::null(),
            null_markers: ptr::null(),
            override_names: ptr::null(),
            override_dtypes: ptr::null(),
            overrides_len: 0,
            new_columns: ptr::null(),
        }
    }
}

fn read_csv_v3(path: *const c_char, b: CsvBlocks) -> *mut DataFrame {
    dataframe_read_csv_v3(
        path,
        CompatCsvOptions::default(),
        b.comment_prefix,
        ptr::null(),
        b.null_values,
        b.null_columns,
        b.null_markers,
        b.override_names,
        b.override_dtypes,
        b.overrides_len,
        b.new_columns,
        ptr::null(),
        ptr::null(),
        0,
    )
}

fn scan_csv_v3(path: *const c_char, b: CsvBlocks) -> *mut LazyFrame {
    lazyframe_scan_csv_v3(
        path,
        CompatCsvOptions::default(),
        b.comment_prefix,
        ptr::null(),
        b.null_values,
        b.null_columns,
        b.null_markers,
        b.override_names,
        b.override_dtypes,
        b.overrides_len,
        b.new_columns,
        ptr::null(),
        ptr::null(),
        0,
    )
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
                let prefix = CsvBlocks {
                    comment_prefix: bad,
                    ..Default::default()
                };
                let nulls = CsvBlocks {
                    null_values: bad_list,
                    ..Default::default()
                };
                read_csv_v3(csv.as_ptr(), prefix).is_null()
                    && read_csv_v3(csv.as_ptr(), nulls).is_null()
            }),
        ),
        (
            "lazyframe_scan_csv_v3",
            Box::new(|| {
                let renamed = CsvBlocks {
                    new_columns: bad_list,
                    ..Default::default()
                };
                scan_csv_v3(csv.as_ptr(), renamed).is_null()
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
    let pointee = dir.path().join("pointee.csv");
    let link = dir.path().join("link.csv");
    std::os::unix::fs::symlink(&pointee, &link).expect("symlink");
    let linked = cstr(link.to_str().unwrap());
    assert_ne!(
        dataframe_write_csv_with_options_v2(
            df,
            linked.as_ptr(),
            CompatCsvWriteOptions::default(),
            ptr::null(),
            bad,
            ptr::null(),
            ptr::null(),
            ptr::null(),
        ),
        0
    );
    assert_eq!(recorded_error(), Some(StrError::Truncated.to_string()));
    assert!(
        !pointee.exists(),
        "a malformed block opened the dangling link's pointee"
    );
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
        let blocks = CsvBlocks {
            null_columns: columns,
            null_markers: markers,
            override_names: names,
            override_dtypes: &float64,
            overrides_len: 1,
            ..Default::default()
        };
        assert!(read_csv_v3(p.as_ptr(), blocks).is_null());
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
    for (kind, indices) in [(0, ptr::null()), (2, [0i64].as_ptr())] {
        let selected = dataframe_read_parquet_with_options_v2(
            q.as_ptr(),
            CompatParquetReadOptions::default(),
            ptr::null(),
            ptr::null(),
            kind,
            one.as_ptr(),
            indices,
            1,
        );
        assert!(selected.is_null());
        assert_eq!(
            recorded_error(),
            Some(format!(
                "column names are given with column selection {}",
                kind
            ))
        );
    }
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
    let schema_json = dataframe_read_json_with_options_v2(
        j.as_ptr(),
        CompatJsonOptions {
            has_schema: true,
            schema_len: 1,
            ..Default::default()
        },
        two.as_ptr(),
        &float64,
        ptr::null(),
        ptr::null(),
    );
    assert!(schema_json.is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("2 schema names are given for 1 dtypes")
    );
    let ndjson = dir.path().join("x.ndjson");
    let n = cstr(ndjson.to_str().unwrap());
    assert_eq!(
        dataframe_write_ndjson_with_options(df, n.as_ptr(), 0, false, 0, true),
        0
    );
    let ndjson_rows: [(&str, CompatNdjsonOptions, StrListArg, StrListArg); 2] = [
        (
            "2 schema names are given for 1 dtypes",
            CompatNdjsonOptions {
                has_schema: true,
                schema_len: 1,
                ..Default::default()
            },
            two.as_ptr(),
            ptr::null(),
        ),
        (
            "2 override names are given for 1 dtypes",
            CompatNdjsonOptions {
                overrides_len: 1,
                ..Default::default()
            },
            ptr::null(),
            two.as_ptr(),
        ),
    ];
    for (reason, options, schema, overrides) in ndjson_rows {
        let read = dataframe_read_ndjson_with_options_v2(
            n.as_ptr(),
            options,
            schema,
            &float64,
            overrides,
            &float64,
            ptr::null(),
            ptr::null(),
        );
        assert!(read.is_null());
        assert_eq!(recorded_error().as_deref(), Some(reason));
        let scanned = lazyframe_scan_ndjson_with_options_v2(
            n.as_ptr(),
            options,
            schema,
            &float64,
            overrides,
            &float64,
            ptr::null(),
            ptr::null(),
        );
        assert!(scanned.is_null());
        assert_eq!(recorded_error().as_deref(), Some(reason));
    }
    dataframe_drop(df);
    series_drop(xs);
}
