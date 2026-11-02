use super::test_util::*;
use super::*;
use std::path::{Path, PathBuf};

#[derive(Clone, Default)]
struct Ndjson {
    options: CompatNdjsonOptions,
    schema: Option<Vec<(String, CompatDType)>>,
    overrides: Vec<(String, CompatDType)>,
    row_index_name: Option<String>,
    include_file_paths: Option<String>,
}

fn dtype(tag: CompatDTypeTag) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    }
}

fn fields(pairs: &[(&str, CompatDTypeTag)]) -> Vec<(String, CompatDType)> {
    pairs
        .iter()
        .map(|(name, tag)| (name.to_string(), dtype(*tag)))
        .collect()
}

type Entry<T> = extern "C" fn(
    *const c_char,
    CompatNdjsonOptions,
    StrListArg,
    *const CompatDType,
    StrListArg,
    *const CompatDType,
    StrArg,
    StrArg,
) -> *mut T;

impl Ndjson {
    fn schema(mut self, pairs: &[(&str, CompatDTypeTag)]) -> Self {
        self.schema = Some(fields(pairs));
        self
    }

    fn overrides(mut self, pairs: &[(&str, CompatDTypeTag)]) -> Self {
        self.overrides = fields(pairs);
        self
    }

    fn with(mut self, f: impl FnOnce(&mut CompatNdjsonOptions)) -> Self {
        f(&mut self.options);
        self
    }

    fn row_index(mut self, name: &str, offset: usize) -> Self {
        self.row_index_name = Some(name.to_string());
        self.options.row_index_offset = offset;
        self
    }

    fn file_paths(mut self, name: &str) -> Self {
        self.include_file_paths = Some(name.to_string());
        self
    }

    fn call<T>(&self, path: &Path, entry: Entry<T>) -> *mut T {
        let p = cstr(path.to_str().unwrap());
        let schema = self.schema.clone().unwrap_or_default();
        let schema_names: Vec<&str> =
            schema.iter().map(|(n, _)| n.as_str()).collect();
        let schema_names = str_list_block(&schema_names);
        let schema_dtypes: Vec<CompatDType> =
            schema.iter().map(|(_, d)| *d).collect();
        let override_names: Vec<&str> =
            self.overrides.iter().map(|(n, _)| n.as_str()).collect();
        let override_names = str_list_block(&override_names);
        let override_dtypes: Vec<CompatDType> =
            self.overrides.iter().map(|(_, d)| *d).collect();
        let row_index = self.row_index_name.as_deref().map(str_block);
        let file_paths = self.include_file_paths.as_deref().map(str_block);
        let name = |b: &Option<Vec<u64>>| {
            b.as_ref().map_or(ptr::null(), |b| b.as_ptr())
        };
        entry(
            p.as_ptr(),
            CompatNdjsonOptions {
                has_schema: self.schema.is_some(),
                schema_len: schema.len(),
                overrides_len: self.overrides.len(),
                ..self.options
            },
            schema_names.as_ptr(),
            schema_dtypes.as_ptr(),
            override_names.as_ptr(),
            override_dtypes.as_ptr(),
            name(&row_index),
            name(&file_paths),
        )
    }

    fn read_outcome(&self, path: &Path) -> Result<DataFrame, String> {
        let out = self.call(path, dataframe_read_ndjson_with_options_v2);
        if out.is_null() {
            return Err(recorded_error().expect("a reason"));
        }
        assert_eq!(recorded_error(), None);
        Ok(unsafe { *Box::from_raw(out) })
    }

    fn read(&self, path: &Path) -> DataFrame {
        self.read_outcome(path).expect("read")
    }

    fn read_err(&self, path: &Path) -> String {
        self.read_outcome(path)
            .expect_err("read unexpectedly succeeded")
    }

    fn scan(&self, path: &Path) -> Result<LazyFrame, String> {
        let lf = self.call(path, lazyframe_scan_ndjson_with_options_v2);
        if lf.is_null() {
            return Err(recorded_error().expect("a reason"));
        }
        Ok(unsafe { *Box::from_raw(lf) })
    }
}

fn write(dir: &Path, name: &str, contents: &str) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, contents).expect("write fixture");
    path
}

const ROWS: &str = "{\"foo\":1,\"bar\":6}\n{\"foo\":2,\"bar\":7.5}\n\
                    {\"foo\":3,\"bar\":null}\n";

fn dtypes(df: &DataFrame) -> Vec<(String, DataType)> {
    df.schema()
        .iter()
        .map(|(name, dtype)| (name.to_string(), dtype.clone()))
        .collect()
}

fn ints(df: &DataFrame, name: &str) -> Vec<Option<i64>> {
    df.column(name)
        .unwrap()
        .cast(&DataType::Int64)
        .unwrap()
        .i64()
        .unwrap()
        .iter()
        .collect()
}

#[test]
fn reads_one_object_a_line() {
    let dir = scratch_dir();
    let path = write(dir.path(), "rows.ndjson", ROWS);
    let df = Ndjson::default().read(&path);
    assert_eq!(
        dtypes(&df),
        vec![
            ("foo".into(), DataType::Int64),
            ("bar".into(), DataType::Float64)
        ]
    );
    let lf = Ndjson::default().scan(&path).expect("scan");
    assert!(lf.collect().unwrap().equals_missing(&df));
}

#[test]
fn a_pattern_or_a_directory_reads_every_file_in_order() {
    let dir = scratch_dir();
    let parts = dir.path().join("parts");
    std::fs::create_dir(&parts).unwrap();
    for (name, x) in [("p2", 20), ("p1", 10), ("p3", 30)] {
        write(
            &parts,
            &format!("{name}.ndjson"),
            &format!("{{\"x\":{}}}\n", x),
        );
    }
    let expected = vec![Some(10), Some(20), Some(30)];
    let pattern = parts.join("p*.ndjson");
    assert_eq!(ints(&Ndjson::default().read(&pattern), "x"), expected);
    assert_eq!(ints(&Ndjson::default().read(&parts), "x"), expected);
    let scanned = Ndjson::default().scan(&pattern).unwrap().collect().unwrap();
    assert_eq!(ints(&scanned, "x"), expected);
    let none = Ndjson::default().read_err(&parts.join("*.none"));
    assert!(none.contains("expanded paths were empty"), "{none}");
    let missing = Ndjson::default().read_err(&parts.join("nope.ndjson"));
    assert!(missing.starts_with("cannot open file: "), "{missing}");
    assert!(Ndjson::default().scan(&parts.join("nope.ndjson")).is_ok());
}

#[test]
fn schema_and_overrides_set_the_dtypes() {
    use CompatDTypeTag as Tag;
    let dir = scratch_dir();
    let path = write(dir.path(), "rows.ndjson", ROWS);
    let df = Ndjson::default()
        .schema(&[("bar", Tag::Float32), ("foo", Tag::Int32)])
        .read(&path);
    assert_eq!(
        dtypes(&df),
        vec![
            ("bar".into(), DataType::Float32),
            ("foo".into(), DataType::Int32)
        ]
    );
    let over = Ndjson::default()
        .overrides(&[("foo", Tag::String)])
        .read(&path);
    assert_eq!(over.column("foo").unwrap().dtype(), &DataType::String);
    assert_eq!(
        Ndjson::default()
            .overrides(&[("zzz", Tag::String)])
            .scan(&path)
            .err(),
        Some("schema overrides name a column not in the file: \"zzz\"".into())
    );
    assert_eq!(
        Ndjson::default()
            .schema(&[("foo", Tag::Int64)])
            .overrides(&[("bar", Tag::String)])
            .read_err(&path),
        "schema overrides name a column not in the schema: \"bar\""
    );
    let both = Ndjson::default()
        .schema(&[("foo", Tag::Int32), ("bar", Tag::Float64)])
        .overrides(&[("foo", Tag::Int64)])
        .read(&path);
    assert_eq!(
        dtypes(&both),
        vec![
            ("foo".into(), DataType::Int64),
            ("bar".into(), DataType::Float64)
        ]
    );
}

#[test]
fn inference_and_errors() {
    let dir = scratch_dir();
    let path = write(dir.path(), "rows.ndjson", ROWS);
    let one = |o: &mut CompatNdjsonOptions| o.infer_schema_length = 1;
    let err = Ndjson::default().with(one).read_err(&path);
    assert!(err.contains("as Int64"), "{err}");
    let array = write(dir.path(), "array.json", "[{\"a\":1}]");
    let err = Ndjson::default().read_err(&array);
    assert!(err.contains("expected to contain JSON object"), "{err}");
    assert!(!err.contains("Resolved plan"), "{err}");
    let ignored = Ndjson::default()
        .with(one)
        .with(|o| o.ignore_errors = true)
        .read(&path);
    assert_eq!(ints(&ignored, "bar"), vec![Some(6), None, None]);
    let all = Ndjson::default()
        .with(|o| o.has_infer_schema_length = false)
        .read(&path);
    assert_eq!(all.column("bar").unwrap().dtype(), &DataType::Float64);
    assert_eq!(
        Ndjson::default()
            .with(|o| o.infer_schema_length = 0)
            .read_err(&path),
        "infer schema length must be positive"
    );
}

#[test]
fn rows_index_and_file_paths() {
    let dir = scratch_dir();
    let path = write(dir.path(), "rows.ndjson", ROWS);
    let first = Ndjson::default()
        .with(|o| {
            o.has_n_rows = true;
            o.n_rows = 2;
        })
        .row_index("i", 10)
        .file_paths("src")
        .with(|o| {
            o.rechunk = true;
            o.low_memory = true;
            o.batch_size = 1;
        })
        .read(&path);
    let names: Vec<String> = first
        .get_column_names()
        .iter()
        .map(|n| n.to_string())
        .collect();
    assert_eq!(names, vec!["i", "foo", "bar", "src"]);
    assert_eq!(first.column("i").unwrap().dtype(), &IDX_DTYPE);
    assert_eq!(ints(&first, "i"), vec![Some(10), Some(11)]);
    let src = first.column("src").unwrap().str().unwrap().get(0).unwrap();
    assert_eq!(src, path.to_str().unwrap());
    let err = Ndjson::default().row_index("i", usize::MAX).read_err(&path);
    assert!(err.starts_with("row index offset "), "{err}");
}

#[test]
fn write_ndjson_writes_a_line_an_object() {
    let dir = scratch_dir();
    let xs = make_i64("x", &[1, 2, 3]);
    let gs = make_str("g", &["a", "b", "c"]);
    let df = make_df(&[xs, gs]);
    let at = |name: &str| cstr(dir.path().join(name).to_str().unwrap());
    let write =
        |path: &CString, compression: u8, check_extension: bool| -> i32 {
            dataframe_write_ndjson_with_options(
                df,
                path.as_ptr(),
                compression,
                false,
                0,
                check_extension,
            )
        };
    let out = at("out.ndjson");
    assert_eq!(write(&out, 0, true), 0);
    let text = std::fs::read_to_string(dir.path().join("out.ndjson")).unwrap();
    assert_eq!(
        text,
        "{\"x\":1,\"g\":\"a\"}\n{\"x\":2,\"g\":\"b\"}\n{\"x\":3,\"g\":\"c\"}\n"
    );
    let back = Ndjson::default().read(&dir.path().join("out.ndjson"));
    assert!(back.equals_missing(unsafe { &*df }));

    assert_ne!(write(&at("out.ndjson.gz"), 0, true), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("check_extension"), "{reason}");
    assert!(!reason.contains("Resolved plan"), "{reason}");
    assert!(!dir.path().join("out.ndjson.gz").exists());
    assert_eq!(write(&at("out.ndjson.gz"), 0, false), 0);
    assert_ne!(write(&at("out.ndjson"), 1, true), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("expected suffix: (.gz)"), "{reason}");
    assert_ne!(write(&at("no/such/out.ndjson"), 0, true), 0);
    assert!(recorded_error().is_some());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn compressed_output_reads_back() {
    let dir = scratch_dir();
    let xs = make_i64("x", &[1, 2, 3]);
    let df = make_df(&[xs]);
    for (name, compression, magic) in [
        ("out.ndjson.gz", 1, &[0x1f, 0x8b][..]),
        ("out.ndjson.zst", 2, &[0x28, 0xb5, 0x2f, 0xfd][..]),
    ] {
        let path = dir.path().join(name);
        let p = cstr(path.to_str().unwrap());
        let status = dataframe_write_ndjson_with_options(
            df,
            p.as_ptr(),
            compression,
            true,
            3,
            true,
        );
        let reason = recorded_error();
        assert_eq!(status, 0, "{name}: {reason:?}");
        assert!(std::fs::read(&path).unwrap().starts_with(magic), "{name}");
        let back = Ndjson::default().read(&path);
        assert!(back.equals_missing(unsafe { &*df }), "{name}");
    }
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn a_compression_signature_reads_as_compressed() {
    let dir = scratch_dir();
    let cases: [(&str, &[u8]); 3] = [
        ("gzip.ndjson", b"\x1f\x8b\x00\x00{\"a\":1}\n"),
        ("zlib.ndjson", b"x^junk\n{\"a\":1}\n"),
        ("zstd.ndjson", b"(\xb5/\xfd{\"a\":1}\n"),
    ];
    for (name, bytes) in cases {
        let path = write_bytes(dir.path(), name, bytes);
        let err = Ndjson::default().read_err(&path);
        assert!(!err.contains("TapeError"), "{name}: {err}");
        assert!(!err.contains("decompress' feature"), "{name}: {err}");
    }
    let late = write_bytes(dir.path(), "late.ndjson", b"{\"a\":1}\nx^junk\n");
    let err = Ndjson::default().read_err(&late);
    assert!(err.contains("TapeError"), "{err}");
}

fn write_bytes(dir: &Path, name: &str, contents: &[u8]) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, contents).expect("write fixture");
    path
}

#[test]
fn a_refused_write_leaves_the_existing_file() {
    let dir = scratch_dir();
    let keep = write(dir.path(), "keep.ndjson", "PRECIOUS");
    let keep_gz = write(dir.path(), "keep.ndjson.gz", "PRECIOUS");
    let bytes: [&[u8]; 2] = [b"p", b"q"];
    let binary = Box::into_raw(Box::new(
        DataFrame::new_infer_height(vec![
            Series::new("a".into(), &[1i64, 2]).into(),
            Series::new("b".into(), &bytes).into(),
        ])
        .unwrap(),
    ));
    let write_to = |df, path: &Path, check_extension| {
        let p = cstr(path.to_str().unwrap());
        dataframe_write_ndjson_with_options(
            df,
            p.as_ptr(),
            0,
            false,
            0,
            check_extension,
        )
    };
    assert_ne!(write_to(binary, &keep, true), 0);
    assert_eq!(
        recorded_error().as_deref(),
        Some("cannot write the binary column \"b\" as JSON")
    );
    let xs = make_i64("x", &[1]);
    let ok = make_df(&[xs]);
    assert_ne!(write_to(ok, &keep_gz, true), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("check_extension"), "{reason}");
    assert!(!reason.contains(".partial"), "{reason}");
    assert_eq!(std::fs::read_to_string(&keep).unwrap(), "PRECIOUS");
    assert_eq!(std::fs::read_to_string(&keep_gz).unwrap(), "PRECIOUS");
    assert_eq!(entries(dir.path()), vec!["keep.ndjson", "keep.ndjson.gz"]);
    assert_eq!(write_to(ok, &keep, true), 0);
    assert_eq!(std::fs::read_to_string(&keep).unwrap(), "{\"x\":1}\n");
    let sub = dir.path().join("sub");
    std::fs::create_dir(&sub).unwrap();
    assert_ne!(write_to(ok, &sub, true), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.starts_with("cannot create file: "), "{reason}");
    assert_eq!(
        entries(dir.path()),
        vec!["keep.ndjson", "keep.ndjson.gz", "sub"]
    );
    dataframe_drop(ok);
    series_drop(xs);
    dataframe_drop(binary);
}

#[test]
fn write_ndjson_refuses_binary_inside_a_list_or_struct() {
    let dir = scratch_dir();
    let path = dir.path().join("nested.ndjson");
    let p = cstr(path.to_str().unwrap());
    let bytes: [&[u8]; 2] = [b"p", b"q"];
    let binary = Series::new("b".into(), &bytes);
    let list = binary.implode().unwrap().into_series();
    let fields = DataFrame::new_infer_height(vec![
        Series::new("a".into(), &[1i64, 2]).into(),
        binary.clone().into(),
    ])
    .unwrap()
    .into_struct("s".into())
    .into_series();
    for (name, series) in [("l", list), ("s", fields)] {
        let df = Box::into_raw(Box::new(
            DataFrame::new_infer_height(vec![series
                .with_name(name.into())
                .into()])
            .unwrap(),
        ));
        assert_ne!(
            dataframe_write_ndjson_with_options(
                df,
                p.as_ptr(),
                0,
                false,
                0,
                true
            ),
            0
        );
        assert_eq!(
            recorded_error(),
            Some(format!("cannot write the binary column {name:?} as JSON"))
        );
        dataframe_drop(df);
    }
    assert!(entries(dir.path()).is_empty());
}
