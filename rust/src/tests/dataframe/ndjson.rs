use super::test_util::*;
use super::*;
use std::path::{Path, PathBuf};

#[derive(Clone, Default)]
struct Ndjson {
    options: CompatNdjsonOptions,
    schema: Option<Vec<(CString, CompatDType)>>,
    overrides: Vec<(CString, CompatDType)>,
    row_index_name: Option<CString>,
    include_file_paths: Option<CString>,
}

fn dtype(tag: CompatDTypeTag) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    }
}

fn fields(pairs: &[(&str, CompatDTypeTag)]) -> Vec<(CString, CompatDType)> {
    pairs
        .iter()
        .map(|(name, tag)| (cstr(name), dtype(*tag)))
        .collect()
}

type Entry<T> = extern "C" fn(
    *const c_char,
    CompatNdjsonOptions,
    *const *const c_char,
    *const CompatDType,
    *const *const c_char,
    *const CompatDType,
    *const c_char,
    *const c_char,
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
        self.row_index_name = Some(cstr(name));
        self.options.row_index_offset = offset;
        self
    }

    fn file_paths(mut self, name: &str) -> Self {
        self.include_file_paths = Some(cstr(name));
        self
    }

    fn call<T>(&self, path: &Path, entry: Entry<T>) -> *mut T {
        let p = cstr(path.to_str().unwrap());
        let schema = self.schema.clone().unwrap_or_default();
        let schema_names: Vec<*const c_char> =
            schema.iter().map(|(n, _)| n.as_ptr()).collect();
        let schema_dtypes: Vec<CompatDType> =
            schema.iter().map(|(_, d)| *d).collect();
        let override_names: Vec<*const c_char> =
            self.overrides.iter().map(|(n, _)| n.as_ptr()).collect();
        let override_dtypes: Vec<CompatDType> =
            self.overrides.iter().map(|(_, d)| *d).collect();
        let name = |s: &Option<CString>| {
            s.as_ref().map_or(ptr::null(), |s| s.as_ptr())
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
            name(&self.row_index_name),
            name(&self.include_file_paths),
        )
    }

    fn read_outcome(&self, path: &Path) -> Result<DataFrame, String> {
        let out = self.call(path, dataframe_read_ndjson_with_options);
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
        let lf = self.call(path, lazyframe_scan_ndjson_with_options);
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
    let dir = tempfile::tempdir().expect("tempdir");
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
    let dir = tempfile::tempdir().expect("tempdir");
    let parts = dir.path().join("parts");
    std::fs::create_dir(&parts).unwrap();
    for (name, x) in [("p2", 20), ("p1", 10), ("p3", 30)] {
        write(
            &parts,
            &format!("{}.ndjson", name),
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
    assert!(none.contains("expanded paths were empty"), "{}", none);
    let missing = Ndjson::default().read_err(&parts.join("nope.ndjson"));
    assert!(missing.starts_with("cannot open file: "), "{}", missing);
    assert!(Ndjson::default().scan(&parts.join("nope.ndjson")).is_ok());
}

#[test]
fn schema_and_overrides_set_the_dtypes() {
    use CompatDTypeTag as Tag;
    let dir = tempfile::tempdir().expect("tempdir");
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
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "rows.ndjson", ROWS);
    let one = |o: &mut CompatNdjsonOptions| o.infer_schema_length = 1;
    let err = Ndjson::default().with(one).read_err(&path);
    assert!(err.contains("as Int64"), "{}", err);
    let array = write(dir.path(), "array.json", "[{\"a\":1}]");
    let err = Ndjson::default().read_err(&array);
    assert!(err.contains("expected to contain JSON object"), "{}", err);
    assert!(!err.contains("Resolved plan"), "{}", err);
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
    let dir = tempfile::tempdir().expect("tempdir");
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
    assert!(err.starts_with("row index offset "), "{}", err);
}

#[test]
fn write_ndjson_writes_a_line_an_object() {
    let dir = tempfile::tempdir().expect("tempdir");
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
    assert!(reason.contains("check_extension"), "{}", reason);
    assert!(!reason.contains("Resolved plan"), "{}", reason);
    assert!(!dir.path().join("out.ndjson.gz").exists());
    assert_eq!(write(&at("out.ndjson.gz"), 0, false), 0);
    assert_ne!(write(&at("out.ndjson"), 1, true), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("expected suffix: (.gz)"), "{}", reason);
    assert_ne!(write(&at("no/such/out.ndjson"), 0, true), 0);
    assert!(recorded_error().is_some());
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

#[test]
fn compressed_output_reads_back() {
    let dir = tempfile::tempdir().expect("tempdir");
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
        assert_eq!(status, 0, "{}: {:?}", name, recorded_error());
        assert!(std::fs::read(&path).unwrap().starts_with(magic), "{}", name);
        let back = Ndjson::default().read(&path);
        assert!(back.equals_missing(unsafe { &*df }), "{}", name);
    }
    dataframe_drop(df);
    series_drop(xs);
}

#[test]
fn a_compression_signature_reads_as_compressed() {
    let dir = tempfile::tempdir().expect("tempdir");
    let cases: [(&str, &[u8]); 3] = [
        ("gzip.ndjson", b"\x1f\x8b\x00\x00{\"a\":1}\n"),
        ("zlib.ndjson", b"x^junk\n{\"a\":1}\n"),
        ("zstd.ndjson", b"(\xb5/\xfd{\"a\":1}\n"),
    ];
    for (name, bytes) in cases {
        let path = write_bytes(dir.path(), name, bytes);
        let err = Ndjson::default().read_err(&path);
        assert!(!err.contains("TapeError"), "{}: {}", name, err);
        assert!(!err.contains("decompress' feature"), "{}: {}", name, err);
    }
    let late = write_bytes(dir.path(), "late.ndjson", b"{\"a\":1}\nx^junk\n");
    let err = Ndjson::default().read_err(&late);
    assert!(err.contains("TapeError"), "{}", err);
}

fn write_bytes(dir: &Path, name: &str, contents: &[u8]) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, contents).expect("write fixture");
    path
}
