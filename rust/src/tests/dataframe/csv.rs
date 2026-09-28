use super::test_util::*;
use super::*;
use std::path::{Path, PathBuf};

#[derive(Default)]
struct Csv {
    options: CompatCsvOptions,
    comment_prefix: Option<CString>,
    null_values: Vec<CString>,
    overrides: Vec<(CString, CompatDType)>,
}

impl Csv {
    fn call<T>(
        &self,
        path: &Path,
        entry: extern "C" fn(
            *const c_char,
            CompatCsvOptions,
            *const c_char,
            *const *const c_char,
            usize,
            *const *const c_char,
            *const CompatDType,
            usize,
        ) -> *mut T,
    ) -> *mut T {
        let p = cstr(path.to_str().unwrap());
        let nulls: Vec<*const c_char> =
            self.null_values.iter().map(|s| s.as_ptr()).collect();
        let names: Vec<*const c_char> =
            self.overrides.iter().map(|(n, _)| n.as_ptr()).collect();
        let dtypes: Vec<CompatDType> =
            self.overrides.iter().map(|(_, d)| *d).collect();
        entry(
            p.as_ptr(),
            self.options,
            self.comment_prefix
                .as_ref()
                .map_or(ptr::null(), |s| s.as_ptr()),
            nulls.as_ptr(),
            nulls.len(),
            names.as_ptr(),
            dtypes.as_ptr(),
            dtypes.len(),
        )
    }

    fn read(&self, path: &Path) -> DataFrame {
        let out = self.call(path, dataframe_read_csv_with_options);
        assert!(!out.is_null(), "read failed: {:?}", recorded_error());
        unsafe { *Box::from_raw(out) }
    }

    fn read_err(&self, path: &Path) -> String {
        let out = self.call(path, dataframe_read_csv_with_options);
        assert!(out.is_null(), "read unexpectedly succeeded");
        recorded_error().expect("a reason")
    }

    fn scan_err(&self, path: &Path) -> String {
        let out = self.call(path, lazyframe_scan_csv_with_options);
        assert!(out.is_null(), "scan unexpectedly succeeded");
        recorded_error().expect("a reason")
    }

    fn scan_collect(&self, path: &Path) -> DataFrame {
        let lf = self.call(path, lazyframe_scan_csv_with_options);
        assert!(!lf.is_null(), "scan failed: {:?}", recorded_error());
        let lf = unsafe { *Box::from_raw(lf) };
        lf.collect().expect("collect")
    }
}

fn dtype(tag: CompatDTypeTag, time_unit: CompatTimeUnit) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: time_unit as i32,
        flags: 0,
        array_width: 0,
    }
}

fn write(dir: &Path, name: &str, contents: &[u8]) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, contents).expect("write fixture");
    path
}

fn int_column_with_late_na() -> String {
    let mut text = String::from("id,delay\n");
    for i in 0..150 {
        text.push_str(&format!("{},{}\n", i, i % 7));
    }
    text.push_str("150,NA\n");
    text
}

const FIXTURES: &[(&str, &str)] = &[
    (
        "iris.csv",
        "sepal_length,sepal_width,petal_length,petal_width,species\n\
         5.1,3.5,1.4,.2,Setosa\n4.9,3,1.4,.2,Setosa\n7,3.2,4.7,1.4,Versicolor\n\
         6.3,3.3,6,2.5,Virginica\n",
    ),
    (
        "mixed.csv",
        "i,f,s,b,d\n1,1.5,a,true,2024-01-01\n,2.5,,false,\n3,,c,,2024-03-01\n",
    ),
    (
        "quoted.csv",
        "name,note\n\"Smith, J\",\"said \"\"hi\"\"\"\nplain,\"two\nlines\"\n",
    ),
    ("one-column.csv", "only\n1\n2\n3\n"),
    ("header-only.csv", "a,b,c\n"),
    ("tsv-as-csv.csv", "a\tb\n1\t2\n"),
    ("crlf.csv", "a,b\r\n1,x\r\n2,y\r\n"),
    ("bom.csv", "\u{feff}a,b\n1,2\n"),
    ("no-final-newline.csv", "a,b\n1,2\n3,4"),
    ("empty-fields.csv", "a,b,c\n,,\n1,,x\n"),
];

#[test]
fn eager_read_matches_the_reader_it_replaced() {
    let dir = tempfile::tempdir().expect("tempdir");
    let late_na = int_column_with_late_na().replace("NA", "7");
    let fixtures = FIXTURES
        .iter()
        .map(|(name, text)| (*name, text.to_string()))
        .chain([("late.csv", late_na)]);
    for (name, text) in fixtures {
        let path = write(dir.path(), name, text.as_bytes());
        let old = CsvReadOptions::default()
            .with_has_header(true)
            .try_into_reader_with_file_path(Some(path.clone()))
            .and_then(|reader| reader.finish())
            .expect("the old reader");
        let new = Csv::default().read(&path);
        assert_eq!(old.schema(), new.schema(), "{}", name);
        assert!(old.equals_missing(&new), "{}: {:?} vs {:?}", name, old, new);
    }
}

#[test]
fn eager_read_matches_scan_then_collect() {
    let dir = tempfile::tempdir().expect("tempdir");
    for (name, text) in FIXTURES {
        let path = write(dir.path(), name, text.as_bytes());
        let eager = Csv::default().read(&path);
        let lazy = Csv::default().scan_collect(&path);
        assert!(eager.equals_missing(&lazy), "{}", name);
    }
}

#[test]
fn null_values_turn_a_late_marker_into_a_null() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path =
        write(dir.path(), "late.csv", int_column_with_late_na().as_bytes());
    let msg = Csv::default().read_err(&path);
    assert!(msg.contains("NA"), "{:?}", msg);

    let csv = Csv {
        null_values: vec![cstr("NA")],
        ..Default::default()
    };
    let df = csv.read(&path);
    let delay = df.column("delay").unwrap();
    assert_eq!(delay.dtype(), &DataType::Int64);
    assert_eq!(delay.null_count(), 1);
    assert_eq!(df.height(), 151);

    let lazy = csv.scan_collect(&path);
    assert!(df.equals_missing(&lazy));
}

#[test]
fn several_null_values_all_count() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "n.csv", b"x\n1\nNA\n-\n4\n");
    let csv = Csv {
        null_values: vec![cstr("NA"), cstr("-")],
        ..Default::default()
    };
    let x = csv.read(&path).column("x").unwrap().clone();
    assert_eq!(x.dtype(), &DataType::Int64);
    assert_eq!(x.null_count(), 2);
}

#[test]
fn infer_schema_length_none_reads_every_row() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut text = String::from("x\n");
    for i in 0..150 {
        text.push_str(&format!("{}\n", i));
    }
    text.push_str("1.5\n");
    let path = write(dir.path(), "late-float.csv", text.as_bytes());
    Csv::default().read_err(&path);

    let mut csv = Csv::default();
    csv.options.has_infer_schema_length = false;
    let df = csv.read(&path);
    assert_eq!(df.column("x").unwrap().dtype(), &DataType::Float64);
}

#[test]
fn schema_overrides_set_the_named_columns_only() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(
        dir.path(),
        "o.csv",
        b"a,b,c\n1,2024-01-02,x\n2,2024-02-03,y\n",
    );
    let csv = Csv {
        overrides: vec![
            (
                cstr("a"),
                dtype(CompatDTypeTag::Int32, CompatTimeUnit::None),
            ),
            (cstr("b"), dtype(CompatDTypeTag::Date, CompatTimeUnit::None)),
        ],
        ..Default::default()
    };
    let df = csv.read(&path);
    assert_eq!(df.column("a").unwrap().dtype(), &DataType::Int32);
    assert_eq!(df.column("b").unwrap().dtype(), &DataType::Date);
    assert_eq!(df.column("c").unwrap().dtype(), &DataType::String);
}

#[test]
fn an_unsupported_override_names_its_column() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "o.csv", b"a\n1\n");
    let csv = Csv {
        overrides: vec![(
            cstr("a"),
            dtype(CompatDTypeTag::List, CompatTimeUnit::None),
        )],
        ..Default::default()
    };
    let msg = csv.read_err(&path);
    assert!(msg.contains("\"a\""), "{:?}", msg);
}

#[test]
fn ignore_errors_nulls_what_cannot_parse() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path =
        write(dir.path(), "late.csv", int_column_with_late_na().as_bytes());
    let mut csv = Csv::default();
    csv.options.ignore_errors = true;
    let df = csv.read(&path);
    assert_eq!(df.height(), 151);
    assert_eq!(df.column("delay").unwrap().null_count(), 1);
}

#[test]
fn separator_quote_and_comment_options_apply() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(
        dir.path(),
        "opts.txt",
        b"# a comment\na;b\n'x;y';1\n# another\nz;2\n",
    );
    let mut csv = Csv {
        comment_prefix: Some(cstr("#")),
        ..Default::default()
    };
    csv.options.separator = b';';
    csv.options.quote_char = b'\'';
    let df = csv.read(&path);
    assert_eq!(df.shape(), (2, 2));
    assert_eq!(strings(&df, "a"), ["x;y", "z"]);

    let literal = write(dir.path(), "literal.txt", b"a;b\n'x';1\nz;2\n");
    csv.options.has_quote_char = false;
    assert_eq!(strings(&csv.read(&literal), "a"), ["'x'", "z"]);
}

#[test]
fn a_multi_character_comment_prefix_works() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "c.csv", b"x\n//skip\n1\n2\n");
    let csv = Csv {
        comment_prefix: Some(cstr("//")),
        ..Default::default()
    };
    assert_eq!(csv.read(&path).height(), 2);
}

#[test]
fn lossy_utf8_replaces_invalid_bytes() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "bad.csv", b"s\nok\nbad\xff\n");
    Csv::default().read_err(&path);

    let mut csv = Csv::default();
    csv.options.lossy_utf8 = true;
    let df = csv.read(&path);
    assert_eq!(strings(&df, "s"), ["ok", "bad\u{fffd}"]);
}

#[test]
fn try_parse_dates_parses_iso_timestamps() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(
        dir.path(),
        "t.csv",
        b"d,t\n2013-01-01,2013-01-01 05:00:00\n2013-01-02,2013-01-02 06:00:00\n",
    );
    let mut csv = Csv::default();
    assert_eq!(
        csv.read(&path).column("t").unwrap().dtype(),
        &DataType::String
    );
    csv.options.try_parse_dates = true;
    let df = csv.read(&path);
    assert_eq!(df.column("d").unwrap().dtype(), &DataType::Date);
    assert_eq!(
        df.column("t").unwrap().dtype(),
        &DataType::Datetime(TimeUnit::Microseconds, None)
    );
}

#[test]
fn skip_rows_and_n_rows_apply_to_the_eager_read() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "s.csv", b"junk\nx\n1\n2\n3\n");
    let mut csv = Csv::default();
    csv.options.skip_rows = 1;
    csv.options.has_n_rows = true;
    csv.options.n_rows = 2;
    let df = csv.read(&path);
    assert_eq!(df.get_column_names(), ["x"]);
    assert_eq!(df.height(), 2);
}

#[test]
fn a_glob_reads_every_match_in_sorted_order() {
    let dir = tempfile::tempdir().expect("tempdir");
    for (name, row) in [("b.csv", "2"), ("c.csv", "3"), ("a.csv", "1")] {
        write(dir.path(), name, format!("x\n{}\n", row).as_bytes());
    }
    write(dir.path(), "skip.txt", b"x\n99\n");
    let pattern = dir.path().join("*.csv");
    let eager = Csv::default().read(&pattern);
    assert_eq!(read_i64(&eager, "x"), [1, 2, 3]);
    let lazy = Csv::default().scan_collect(&pattern);
    assert!(eager.equals_missing(&lazy));
}

#[test]
fn a_glob_matching_nothing_says_so_at_scan() {
    let dir = tempfile::tempdir().expect("tempdir");
    let pattern = dir.path().join("*.csv");
    let msg = Csv::default().read_err(&pattern);
    assert_eq!(msg, "no files match the pattern");
    let msg = Csv::default().scan_err(&pattern);
    assert_eq!(msg, "no files match the pattern");

    let p = cstr(dir.path().join("*.parquet").to_str().unwrap());
    assert!(dataframe_read_parquet(p.as_ptr()).is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("no files match the pattern")
    );
    assert!(lazyframe_scan_parquet_options(p.as_ptr(), 0, 0).is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("no files match the pattern")
    );
}

#[test]
fn glob_off_reads_a_bracketed_name_literally() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "a1.csv", b"x\n1\n");
    let literal = write(dir.path(), "a[1].csv", b"x\n2\n");
    assert_eq!(read_i64(&Csv::default().read(&literal), "x"), [1]);
    let mut csv = Csv::default();
    csv.options.glob = false;
    assert_eq!(read_i64(&csv.read(&literal), "x"), [2]);
}

#[test]
fn a_missing_file_keeps_the_os_reason_without_the_path() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("nope.csv");
    let msg = Csv::default().read_err(&path);
    assert!(msg.starts_with("cannot open file: "), "{:?}", msg);
    assert!(!msg.contains("nope.csv"), "{:?}", msg);

    let p = cstr(dir.path().join("nope.parquet").to_str().unwrap());
    assert!(dataframe_read_parquet(p.as_ptr()).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(msg.starts_with("cannot open file: "), "{:?}", msg);
}

#[test]
fn an_override_for_an_absent_column_is_an_error_not_a_rename() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "ab.csv", b"a,b\n1,2\n");
    let csv = Csv {
        overrides: vec![
            (
                cstr("a"),
                dtype(CompatDTypeTag::Int64, CompatTimeUnit::None),
            ),
            (
                cstr("zzz"),
                dtype(CompatDTypeTag::Float32, CompatTimeUnit::None),
            ),
        ],
        ..Default::default()
    };
    let expected = "schema overrides name columns not in the file: \"zzz\"";
    assert_eq!(csv.read_err(&path), expected);
    assert_eq!(csv.scan_err(&path), expected);
}

#[test]
fn separate_files_are_read_in_one_order_with_one_limit() {
    let dir = tempfile::tempdir().expect("tempdir");
    for (name, rows) in
        [("p0.csv", "5\n6"), ("p1.csv", "1\n2"), ("p2.csv", "3\n4")]
    {
        write(dir.path(), name, format!("x\n{}\n", rows).as_bytes());
    }
    let pattern = dir.path().join("p*.csv");
    assert_eq!(
        read_i64(&Csv::default().read(&pattern), "x"),
        [5, 6, 1, 2, 3, 4]
    );
    let mut csv = Csv::default();
    csv.options.has_n_rows = true;
    csv.options.n_rows = 3;
    assert_eq!(read_i64(&csv.read(&pattern), "x"), [5, 6, 1]);
}

#[test]
fn files_with_different_headers_do_not_stack() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "a.csv", b"x\n1\n");
    write(dir.path(), "b.csv", b"y\n2\n");
    Csv::default().read_err(&dir.path().join("*.csv"));
}

#[test]
fn parquet_reads_a_glob_in_sorted_order() {
    let dir = tempfile::tempdir().expect("tempdir");
    for (name, value) in [("b.parquet", 2), ("a.parquet", 1)] {
        let xs = make_i64("x", &[value]);
        let df = make_df(&[xs]);
        let p = cstr(dir.path().join(name).to_str().unwrap());
        assert_eq!(dataframe_write_parquet(df, p.as_ptr()), 0);
        dataframe_drop(df);
        series_drop(xs);
    }
    let pattern = cstr(dir.path().join("*.parquet").to_str().unwrap());
    let out = dataframe_read_parquet(pattern.as_ptr());
    assert!(!out.is_null(), "{:?}", recorded_error());
    let df = unsafe { *Box::from_raw(out) };
    assert_eq!(read_i64(&df, "x"), [1, 2]);
}

#[test]
fn parquet_single_file_read_matches_the_reader_it_replaced() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("one.parquet");
    let mut expected = DataFrame::new(vec![
        Series::new("i", [Some(1i64), None, Some(3)]),
        Series::new("s", [Some("a"), Some("b"), None]),
        Series::new("f", [1.5f64, 2.5, 3.5]),
    ])
    .unwrap();
    let file = std::fs::File::create(&path).unwrap();
    ParquetWriter::new(file).finish(&mut expected).unwrap();

    let old = ParquetReader::new(std::fs::File::open(&path).unwrap())
        .finish()
        .unwrap();
    let p = cstr(path.to_str().unwrap());
    let out = dataframe_read_parquet(p.as_ptr());
    assert!(!out.is_null(), "{:?}", recorded_error());
    let new = unsafe { *Box::from_raw(out) };
    assert_eq!(old.schema(), new.schema());
    assert!(old.equals_missing(&new));
}

#[test]
fn a_single_parquet_file_under_a_hive_directory_gains_no_columns() {
    let dir = tempfile::tempdir().expect("tempdir");
    let hive = dir.path().join("year=2013");
    std::fs::create_dir(&hive).unwrap();
    let path = hive.join("one.parquet");
    let mut df = DataFrame::new(vec![Series::new("x", [1i64, 2])]).unwrap();
    let file = std::fs::File::create(&path).unwrap();
    ParquetWriter::new(file).finish(&mut df).unwrap();

    let p = cstr(path.to_str().unwrap());
    let out = dataframe_read_parquet(p.as_ptr());
    assert!(!out.is_null(), "{:?}", recorded_error());
    let back = unsafe { *Box::from_raw(out) };
    assert_eq!(back.get_column_names(), ["x"]);
}

#[test]
fn an_eager_read_of_a_directory_is_refused() {
    let dir = tempfile::tempdir().expect("tempdir");
    write(dir.path(), "a.csv", b"x\n1\n");
    write(dir.path(), "notes.txt", b"x\n99\n");
    let msg = Csv::default().read_err(dir.path());
    assert!(msg.contains("is a directory"), "{:?}", msg);
}

#[test]
fn undecodable_null_values_are_reported() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "x.csv", b"x\n1\n");
    let bad = [0xffu8, 0];
    let nulls = [bad.as_ptr() as *const c_char];
    let p = cstr(path.to_str().unwrap());
    let out = dataframe_read_csv_with_options(
        p.as_ptr(),
        CompatCsvOptions::default(),
        ptr::null(),
        nulls.as_ptr(),
        1,
        ptr::null(),
        ptr::null(),
        0,
    );
    assert!(out.is_null());
    let msg = recorded_error().expect("a reason");
    assert!(msg.contains("null values"), "{:?}", msg);
}

fn strings(df: &DataFrame, name: &str) -> Vec<String> {
    df.column(name)
        .unwrap()
        .str()
        .unwrap()
        .into_iter()
        .map(|v| v.expect("no nulls").to_string())
        .collect()
}

fn read_i64(df: &DataFrame, name: &str) -> Vec<i64> {
    df.column(name)
        .unwrap()
        .i64()
        .unwrap()
        .into_no_null_iter()
        .collect()
}
