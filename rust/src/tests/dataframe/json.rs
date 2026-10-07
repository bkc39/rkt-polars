use super::test_util::*;
use super::*;
use std::path::{Path, PathBuf};

#[derive(Clone, Default)]
struct Json {
    options: CompatJsonOptions,
    schema: Option<Vec<(CString, CompatDType)>>,
    overrides: Vec<(CString, CompatDType)>,
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

impl Json {
    fn schema(mut self, pairs: &[(&str, CompatDTypeTag)]) -> Self {
        self.schema = Some(fields(pairs));
        self
    }

    fn overrides(mut self, pairs: &[(&str, CompatDTypeTag)]) -> Self {
        self.overrides = fields(pairs);
        self
    }

    fn infer_schema_length(mut self, rows: Option<usize>) -> Self {
        self.options.has_infer_schema_length = rows.is_some();
        self.options.infer_schema_length = rows.unwrap_or(0);
        self
    }

    fn outcome(&self, path: &Path) -> Result<DataFrame, String> {
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
        let options = CompatJsonOptions {
            has_schema: self.schema.is_some(),
            schema_len: schema.len(),
            overrides_len: self.overrides.len(),
            ..self.options
        };
        let out = dataframe_read_json_with_options(
            p.as_ptr(),
            options,
            schema_names.as_ptr(),
            schema_dtypes.as_ptr(),
            override_names.as_ptr(),
            override_dtypes.as_ptr(),
        );
        if out.is_null() {
            return Err(recorded_error().expect("a reason"));
        }
        assert_eq!(recorded_error(), None);
        Ok(unsafe { *Box::from_raw(out) })
    }

    fn read(&self, path: &Path) -> DataFrame {
        self.outcome(path).expect("read")
    }

    fn read_err(&self, path: &Path) -> String {
        self.outcome(path).expect_err("read unexpectedly succeeded")
    }
}

fn write(dir: &Path, name: &str, contents: &str) -> PathBuf {
    let path = dir.join(name);
    std::fs::write(&path, contents).expect("write fixture");
    path
}

const ROWS: &str =
    r#"[{"foo":1,"bar":6},{"foo":2,"bar":7.5},{"foo":3,"bar":null}]"#;

fn dtypes(df: &DataFrame) -> Vec<(String, DataType)> {
    df.schema()
        .iter()
        .map(|(name, dtype)| (name.to_string(), dtype.clone()))
        .collect()
}

#[test]
fn reads_an_array_of_objects() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "rows.json", ROWS);
    let df = Json::default().read(&path);
    assert_eq!(
        dtypes(&df),
        vec![
            ("foo".into(), DataType::Int64),
            ("bar".into(), DataType::Float64)
        ]
    );
    assert_eq!(df.height(), 3);
}

#[test]
fn a_schema_sets_the_columns_and_their_order() {
    use CompatDTypeTag as Tag;
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "rows.json", ROWS);
    let df = Json::default()
        .schema(&[
            ("bar", Tag::Float32),
            ("foo", Tag::Int32),
            ("baz", Tag::String),
        ])
        .read(&path);
    assert_eq!(
        dtypes(&df),
        vec![
            ("bar".into(), DataType::Float32),
            ("foo".into(), DataType::Int32),
            ("baz".into(), DataType::String)
        ]
    );
    assert_eq!(df.column("baz").unwrap().null_count(), 3);
    let subset = Json::default().schema(&[("foo", Tag::Int8)]).read(&path);
    assert_eq!(dtypes(&subset), vec![("foo".into(), DataType::Int8)]);
}

#[test]
fn overrides_change_inferred_dtypes() {
    use CompatDTypeTag as Tag;
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "rows.json", ROWS);
    let df = Json::default()
        .overrides(&[("foo", Tag::String)])
        .read(&path);
    assert_eq!(
        dtypes(&df),
        vec![
            ("foo".into(), DataType::String),
            ("bar".into(), DataType::Float64)
        ]
    );
    let both = Json::default()
        .schema(&[("foo", Tag::Int32), ("bar", Tag::Float32)])
        .overrides(&[("foo", Tag::Int64)])
        .read(&path);
    assert_eq!(
        dtypes(&both),
        vec![
            ("foo".into(), DataType::Int64),
            ("bar".into(), DataType::Float32)
        ]
    );
}

#[test]
fn an_override_for_an_absent_column_is_named() {
    use CompatDTypeTag as Tag;
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "rows.json", ROWS);
    assert_eq!(
        Json::default()
            .overrides(&[("zzz", Tag::String)])
            .read_err(&path),
        "schema overrides name a column not in the file: \"zzz\""
    );
    assert_eq!(
        Json::default()
            .schema(&[("foo", Tag::Int64)])
            .overrides(&[("bar", Tag::String)])
            .read_err(&path),
        "schema overrides name a column not in the schema: \"bar\""
    );
}

#[test]
fn inference_reads_the_rows_it_is_given() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "rows.json", ROWS);
    let one = Json::default().infer_schema_length(Some(1)).read(&path);
    assert_eq!(one.column("bar").unwrap().dtype(), &DataType::Int64);
    let all = Json::default().infer_schema_length(None).read(&path);
    assert_eq!(all.column("bar").unwrap().dtype(), &DataType::Float64);
    let ragged = write(dir.path(), "ragged.json", r#"[{"a":1},{"b":2}]"#);
    let err = Json::default()
        .infer_schema_length(Some(1))
        .read_err(&ragged);
    assert!(err.contains("infer_schema_length"), "{}", err);
    assert_eq!(
        Json::default().infer_schema_length(Some(0)).read_err(&path),
        "infer schema length must be positive"
    );
}

#[test]
fn failures_record_their_cause() {
    let dir = tempfile::tempdir().expect("tempdir");
    let missing = Json::default().read_err(&dir.path().join("nope.json"));
    assert!(missing.starts_with("cannot open file: "), "{}", missing);
    assert_eq!(
        Json::default().read_err(dir.path()),
        "cannot open file: it is a directory"
    );
    let numbers = write(dir.path(), "numbers.json", "[1,2,3]");
    assert_eq!(
        Json::default().read_err(&numbers),
        "can only deserialize json objects"
    );
    let lines = write(dir.path(), "lines.json", "{\"a\":1}\n{\"a\":2}\n");
    assert!(Json::default().outcome(&lines).is_err());
}

#[test]
fn an_empty_array_is_an_empty_frame() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "empty.json", "[]");
    assert_eq!(Json::default().read(&path).shape(), (0, 0));
    let typed = Json::default()
        .schema(&[("a", CompatDTypeTag::Int64)])
        .read(&path);
    assert_eq!(typed.shape(), (0, 1));
}

#[test]
fn write_json_writes_an_array_that_reads_back() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("out.json");
    let xs = make_i64("x", &[1, 2, 3]);
    let gs = make_str("g", &["a", "b", "c"]);
    let df = make_df(&[xs, gs]);
    let p = cstr(path.to_str().unwrap());
    assert_eq!(dataframe_write_json(df, p.as_ptr()), 0);
    assert_eq!(
        std::fs::read_to_string(&path).unwrap(),
        r#"[{"x":1,"g":"a"},{"x":2,"g":"b"},{"x":3,"g":"c"}]"#
    );
    let back = Json::default().read(&path);
    assert!(back.equals_missing(unsafe { &*df }));
    let nowhere = cstr(dir.path().join("no/such/out.json").to_str().unwrap());
    assert_ne!(dataframe_write_json(df, nowhere.as_ptr()), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.starts_with("cannot create file: "), "{}", reason);
    dataframe_drop(df);
    series_drop(xs);
    series_drop(gs);
}

fn leftovers(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

#[test]
fn a_failed_write_leaves_the_existing_file() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "keep.json", "PRECIOUS");
    let p = cstr(path.to_str().unwrap());
    let bytes: [&[u8]; 2] = [b"p", b"q"];
    let df = Box::into_raw(Box::new(
        DataFrame::new_infer_height(vec![
            Series::new("a".into(), &[1i64, 2]).into(),
            Series::new("b".into(), &bytes).into(),
        ])
        .unwrap(),
    ));
    assert_ne!(dataframe_write_json(df, p.as_ptr()), 0);
    assert_eq!(
        recorded_error().as_deref(),
        Some("cannot write the binary column \"b\" as JSON")
    );
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "PRECIOUS");
    assert_eq!(leftovers(dir.path()), vec!["keep.json"]);
    let xs = make_i64("x", &[1]);
    let ok = make_df(&[xs]);
    assert_eq!(dataframe_write_json(ok, p.as_ptr()), 0);
    assert_eq!(std::fs::read_to_string(&path).unwrap(), r#"[{"x":1}]"#);
    assert_eq!(leftovers(dir.path()), vec!["keep.json"]);
    let into_dir = cstr(dir.path().to_str().unwrap());
    assert_ne!(dataframe_write_json(ok, into_dir.as_ptr()), 0);
    let reason = recorded_error().expect("a reason");
    assert!(reason.starts_with("cannot create file: "), "{}", reason);
    assert_eq!(leftovers(dir.path()), vec!["keep.json"]);
    dataframe_drop(ok);
    series_drop(xs);
    dataframe_drop(df);
}
