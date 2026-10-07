use super::test_util::*;
use super::*;
use std::path::{Path, PathBuf};

#[derive(Clone, Default)]
struct Csv {
    options: CompatCsvOptions,
    comment_prefix: Option<CString>,
    row_index_name: Option<CString>,
    null_values: Vec<CString>,
    named_nulls: Vec<(CString, CString)>,
    overrides: Vec<(CString, CompatDType)>,
    new_columns: Vec<CString>,
    columns: Vec<CString>,
    projection: Vec<usize>,
}

type CsvEntry<T> = extern "C" fn(
    *const c_char,
    CompatCsvOptions,
    *const c_char,
    *const c_char,
    *const *const c_char,
    usize,
    *const *const c_char,
    *const *const c_char,
    usize,
    *const *const c_char,
    *const CompatDType,
    usize,
    *const *const c_char,
    usize,
    *const *const c_char,
    usize,
    *const usize,
    usize,
) -> *mut T;

fn pointers(strings: &[CString]) -> Vec<*const c_char> {
    strings.iter().map(|s| s.as_ptr()).collect()
}

fn optional(string: &Option<CString>) -> *const c_char {
    string.as_ref().map_or(ptr::null(), |s| s.as_ptr())
}

impl Csv {
    fn call<T>(&self, path: &Path, entry: CsvEntry<T>) -> *mut T {
        let p = cstr(path.to_str().unwrap());
        let nulls = pointers(&self.null_values);
        let null_columns: Vec<*const c_char> =
            self.named_nulls.iter().map(|(c, _)| c.as_ptr()).collect();
        let null_markers: Vec<*const c_char> =
            self.named_nulls.iter().map(|(_, m)| m.as_ptr()).collect();
        let names: Vec<*const c_char> =
            self.overrides.iter().map(|(n, _)| n.as_ptr()).collect();
        let dtypes: Vec<CompatDType> =
            self.overrides.iter().map(|(_, d)| *d).collect();
        let new_columns = pointers(&self.new_columns);
        let columns = pointers(&self.columns);
        entry(
            p.as_ptr(),
            self.options,
            optional(&self.comment_prefix),
            optional(&self.row_index_name),
            nulls.as_ptr(),
            nulls.len(),
            null_columns.as_ptr(),
            null_markers.as_ptr(),
            null_columns.len(),
            names.as_ptr(),
            dtypes.as_ptr(),
            dtypes.len(),
            new_columns.as_ptr(),
            new_columns.len(),
            columns.as_ptr(),
            columns.len(),
            self.projection.as_ptr(),
            self.projection.len(),
        )
    }

    fn read(&self, path: &Path) -> DataFrame {
        let out = self.call(path, dataframe_read_csv_v2);
        assert!(!out.is_null(), "read failed: {:?}", recorded_error());
        unsafe { *Box::from_raw(out) }
    }

    fn read_err(&self, path: &Path) -> String {
        let out = self.call(path, dataframe_read_csv_v2);
        assert!(out.is_null(), "read unexpectedly succeeded");
        recorded_error().expect("a reason")
    }

    fn scan_err(&self, path: &Path) -> String {
        let out = self.call(path, lazyframe_scan_csv_v2);
        assert!(out.is_null(), "scan unexpectedly succeeded");
        recorded_error().expect("a reason")
    }

    fn scan_collect(&self, path: &Path) -> DataFrame {
        let lf = self.call(path, lazyframe_scan_csv_v2);
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

type Outcome = Result<DataFrame, String>;

impl Csv {
    fn read_outcome(&self, path: &Path) -> Outcome {
        let out = self.call(path, dataframe_read_csv_v2);
        if out.is_null() {
            return Err(recorded_error().expect("a reason"));
        }
        Ok(unsafe { *Box::from_raw(out) })
    }

    fn scan_outcome(&self, path: &Path) -> Outcome {
        let lf = self.call(path, lazyframe_scan_csv_v2);
        if lf.is_null() {
            return Err(recorded_error().expect("a reason"));
        }
        let out = lazyframe_collect(lf);
        lazyframe_drop(lf);
        if out.is_null() {
            return Err(recorded_error().expect("a reason"));
        }
        Ok(unsafe { *Box::from_raw(out) })
    }
}

fn same_outcome(a: &Outcome, b: &Outcome) -> bool {
    match (a, b) {
        (Ok(a), Ok(b)) => a.schema() == b.schema() && a.equals_missing(b),
        (Err(a), Err(b)) => a == b,
        _ => false,
    }
}

fn one_file_pattern(path: &Path) -> PathBuf {
    let name = path.file_name().unwrap().to_str().unwrap();
    let mut chars = name.chars();
    let first = chars.next().unwrap();
    path.with_file_name(format!("[{}]{}", first, chars.as_str()))
}

const OPTION_FIXTURES: &[(&str, &[u8])] = &[
    ("a.csv", b"a,b,d\n1,x,2024-01-01\n2,NA,2024-01-02\n-,y,\n"),
    ("late-float.csv", b"a\n1\n2\n3\n4.5\n"),
    ("semi.txt", b"# note\na;b\n'x;y';1\n# mid\nz;2\n"),
    ("slashed.csv", b"a,b\n//skip\n1,2\n3,4\n"),
    (
        "times.csv",
        b"t,d,a\n05:00:00,2020-01-02,2013-01-01 05:00:00\n",
    ),
    ("latin.csv", b"a\ncaf\xe9\n"),
    ("tabs.tsv", b"a\tb\nNA\t2\n3\t-\n"),
    ("eol.csv", b"a,b;1,x;2,y;"),
    ("ragged.csv", b"a,b\n1,x\n2,y,extra\n3\n"),
    ("comma-decimals.csv", b"a;b\n1,5;x\n2,25;y\n"),
    ("quoted-decimals.csv", b"a,b\n\"1,5\",x\n\"2,25\",y\n"),
    (
        "preamble.csv",
        b"junk \"quoted\nstill junk\na,b\n1,x\n2,y\n3,z\n",
    ),
    ("missing.csv", b"a,b\n1,\n,x\n"),
];

fn option_cases() -> Vec<(&'static str, Csv)> {
    let case = |label, set: fn(&mut Csv)| {
        let mut csv = Csv::default();
        set(&mut csv);
        (label, csv)
    };
    let int32 = dtype(CompatDTypeTag::Int32, CompatTimeUnit::None);
    let float64 = dtype(CompatDTypeTag::Float64, CompatTimeUnit::None);
    let time = dtype(CompatDTypeTag::Time, CompatTimeUnit::None);
    let mut cases = vec![
        case("defaults", |_| {}),
        case("no header", |c| c.options.has_header = false),
        case("separator ;", |c| c.options.separator = b';'),
        case("separator tab", |c| c.options.separator = b'\t'),
        case("quote '", |c| c.options.quote_char = b'\''),
        case("no quoting", |c| c.options.has_quote_char = false),
        case("comment #", |c| c.comment_prefix = Some(cstr("#"))),
        case("comment //", |c| c.comment_prefix = Some(cstr("//"))),
        case("skip rows", |c| c.options.skip_rows = 1),
        case("n rows 2", |c| {
            c.options.has_n_rows = true;
            c.options.n_rows = 2;
        }),
        case("n rows 0", |c| {
            c.options.has_n_rows = true;
            c.options.n_rows = 0;
        }),
        case("null NA", |c| c.null_values = vec![cstr("NA")]),
        case("null NA and -", |c| {
            c.null_values = vec![cstr("NA"), cstr("-")]
        }),
        case("infer every row", |c| {
            c.options.has_infer_schema_length = false
        }),
        case("infer 0", |c| c.options.infer_schema_length = 0),
        case("infer 1", |c| c.options.infer_schema_length = 1),
        case("ignore errors", |c| c.options.ignore_errors = true),
        case("try parse dates", |c| c.options.try_parse_dates = true),
        case("lossy utf8", |c| c.options.lossy_utf8 = true),
        case("glob off", |c| c.options.glob = false),
        case("; ' # together", |c| {
            c.options.separator = b';';
            c.options.quote_char = b'\'';
            c.comment_prefix = Some(cstr("#"));
        }),
        case("NA, skip and n rows together", |c| {
            c.null_values = vec![cstr("NA"), cstr("-")];
            c.options.skip_rows = 1;
            c.options.has_header = false;
            c.options.has_n_rows = true;
            c.options.n_rows = 1;
        }),
        case("eol ;", |c| c.options.eol_char = b';'),
        case("truncate ragged lines", |c| {
            c.options.truncate_ragged_lines = true
        }),
        case("decimal comma", |c| c.options.decimal_comma = true),
        case("decimal comma ;", |c| {
            c.options.decimal_comma = true;
            c.options.separator = b';';
        }),
        case("skip lines 2", |c| c.options.skip_lines = 2),
        case("skip rows after header", |c| {
            c.options.skip_rows_after_header = 1
        }),
        case("empty is no error", |c| c.options.raise_if_empty = false),
        case("missing utf8 is empty", |c| {
            c.options.missing_utf8_is_empty_string = true
        }),
        case("row index i from 10", |c| {
            c.row_index_name = Some(cstr("i"));
            c.options.row_index_offset = 10;
        }),
        case("row index a", |c| c.row_index_name = Some(cstr("a"))),
        case("row index, n rows, skip after header", |c| {
            c.row_index_name = Some(cstr("i"));
            c.options.has_n_rows = true;
            c.options.n_rows = 1;
            c.options.skip_rows_after_header = 1;
        }),
        case("null NA in a", |c| {
            c.named_nulls = vec![(cstr("a"), cstr("NA"))]
        }),
        case("null in a and b", |c| {
            c.named_nulls =
                vec![(cstr("a"), cstr("-")), (cstr("b"), cstr("NA"))]
        }),
        case("null in an absent column", |c| {
            c.named_nulls = vec![(cstr("zzz"), cstr("NA"))]
        }),
        case("new columns x", |c| c.new_columns = vec![cstr("x")]),
        case("new columns x y z w v", |c| {
            c.new_columns = ["x", "y", "z", "w", "v"].map(cstr).to_vec()
        }),
        case("new columns b", |c| c.new_columns = vec![cstr("b")]),
        case("new columns, no header", |c| {
            c.options.has_header = false;
            c.new_columns = vec![cstr("x"), cstr("y")];
        }),
        case("new columns, override and null by new name", |c| {
            c.new_columns = vec![cstr("x")];
            c.overrides = vec![(
                cstr("x"),
                dtype(CompatDTypeTag::String, CompatTimeUnit::None),
            )];
            c.named_nulls = vec![(cstr("x"), cstr("-"))];
        }),
        case("new columns, override by old name", |c| {
            c.new_columns = vec![cstr("x")];
            c.overrides = vec![(
                cstr("a"),
                dtype(CompatDTypeTag::String, CompatTimeUnit::None),
            )];
        }),
        case("new columns and row index x", |c| {
            c.new_columns = vec![cstr("x")];
            c.row_index_name = Some(cstr("x"));
        }),
        case("new columns and row index i", |c| {
            c.new_columns = vec![cstr("x")];
            c.row_index_name = Some(cstr("i"));
        }),
        case("columns b a", |c| c.columns = vec![cstr("b"), cstr("a")]),
        case("columns zzz", |c| c.columns = vec![cstr("zzz")]),
        case("columns 1 0", |c| c.projection = vec![1, 0]),
        case("columns 7", |c| c.projection = vec![7]),
        case("columns, row index and new columns", |c| {
            c.columns = vec![cstr("x")];
            c.new_columns = vec![cstr("x")];
            c.row_index_name = Some(cstr("i"));
        }),
        case("columns 0 and row index", |c| {
            c.projection = vec![0];
            c.row_index_name = Some(cstr("i"));
        }),
        case("columns and n rows", |c| {
            c.projection = vec![0];
            c.options.has_n_rows = true;
            c.options.n_rows = 1;
        }),
    ];
    for (label, overrides) in [
        ("override a int32", vec![(cstr("a"), int32)]),
        ("override a float64", vec![(cstr("a"), float64)]),
        (
            "override a and t time",
            vec![(cstr("a"), float64), (cstr("t"), time)],
        ),
        ("override an absent column", vec![(cstr("zzz"), float64)]),
    ] {
        cases.push((
            label,
            Csv {
                overrides,
                ..Default::default()
            },
        ));
    }
    cases
}

const EAGER_ONLY_OUTCOMES: &[(&str, &str)] = &[
    ("separator ;", "quoted.csv"),
    ("separator tab", "quoted.csv"),
    ("decimal comma ;", "quoted.csv"),
    ("n rows 0", "latin.csv"),
    ("n rows 0", "ragged.csv"),
    ("n rows 0", "comma-decimals.csv"),
];

#[test]
fn an_empty_file_is_an_error_unless_raise_if_empty_is_off() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "empty.csv", b"");
    let mut csv = Csv::default();
    assert_eq!(csv.read_err(&path), "no data: empty CSV");
    assert_eq!(csv.scan_outcome(&path).unwrap_err(), "no data: empty CSV");
    csv.options.raise_if_empty = false;
    let eager = csv.read(&path);
    assert_eq!(eager.shape(), (0, 0));
    assert!(same_outcome(&Ok(eager), &csv.scan_outcome(&path)));
}

#[test]
fn the_eager_reader_matches_the_glob_and_scan_paths_for_every_option() {
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures = FIXTURES
        .iter()
        .map(|(name, text)| (*name, text.as_bytes()))
        .chain(OPTION_FIXTURES.iter().copied());
    let paths: Vec<PathBuf> = fixtures
        .map(|(name, contents)| write(dir.path(), name, contents))
        .collect();
    let mut outcomes = (0, 0);
    let mut mismatches = Vec::new();
    for (label, csv) in option_cases() {
        let mut globbed = csv.clone();
        globbed.options.glob = true;
        for path in &paths {
            let eager = csv.read_outcome(path);
            let glob = globbed.read_outcome(&one_file_pattern(path));
            let scan = csv.scan_outcome(path);
            let name = path.file_name().unwrap().to_str().unwrap();
            let agree =
                same_outcome(&eager, &glob) && same_outcome(&eager, &scan);
            let expected = EAGER_ONLY_OUTCOMES.contains(&(label, name));
            if agree == expected {
                mismatches.push(format!(
                    "{} on {}: eager {:?}, glob {:?}, scan {:?}",
                    label, name, eager, glob, scan
                ));
            }
            if expected {
                assert!(eager.is_err() && same_outcome(&glob, &scan));
            }
            match eager {
                Ok(_) => outcomes.0 += 1,
                Err(_) => outcomes.1 += 1,
            }
        }
    }
    assert!(mismatches.is_empty(), "{}", mismatches.join("\n"));
    assert!(outcomes.0 > 300 && outcomes.1 > 50, "{:?}", outcomes);
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
fn a_time_override_parses_times_of_day() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "t.csv", b"t,d\n05:00:00,1h\n06:30:15,2h\n");
    let time = Csv {
        overrides: vec![(
            cstr("t"),
            dtype(CompatDTypeTag::Time, CompatTimeUnit::None),
        )],
        ..Default::default()
    };
    let df = time.read(&path);
    let t = df.column("t").unwrap();
    assert_eq!(t.dtype(), &DataType::Time);
    assert_eq!(t.null_count(), 0);
    let nanos = t.cast(&DataType::Int64).unwrap();
    assert_eq!(
        nanos.i64().unwrap().get(1),
        Some((6 * 3600 + 30 * 60 + 15) * 1_000_000_000)
    );

    let duration = Csv {
        overrides: vec![(
            cstr("d"),
            dtype(CompatDTypeTag::Duration, CompatTimeUnit::Microseconds),
        )],
        ..Default::default()
    };
    let msg = duration.read_err(&path);
    assert!(msg.contains("duration"), "{:?}", msg);
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

fn empty_expansion(msg: &str) -> bool {
    msg.starts_with("failed to retrieve ")
        && msg.contains(": expanded paths were empty (path expansion input: ")
}

#[test]
fn a_glob_matching_nothing_says_so_at_collect() {
    let dir = tempfile::tempdir().expect("tempdir");
    let pattern = dir.path().join("*.csv");
    let msg = Csv::default().read_err(&pattern);
    assert!(empty_expansion(&msg), "{:?}", msg);
    let lf = Csv::default().call(&pattern, lazyframe_scan_csv_v2);
    assert!(!lf.is_null(), "{:?}", recorded_error());
    assert!(lazyframe_collect(lf).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(empty_expansion(&msg), "{:?}", msg);
    lazyframe_drop(lf);

    let p = cstr(dir.path().join("*.parquet").to_str().unwrap());
    assert!(dataframe_read_parquet(p.as_ptr()).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(empty_expansion(&msg), "{:?}", msg);
    let lf = lazyframe_scan_parquet_options(p.as_ptr(), 0, 0);
    assert!(!lf.is_null(), "{:?}", recorded_error());
    assert!(lazyframe_collect(lf).is_null());
    let msg = recorded_error().expect("a reason");
    assert!(empty_expansion(&msg), "{:?}", msg);
    lazyframe_drop(lf);
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
fn an_override_for_an_absent_column_is_an_error() {
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
    let mut expected = DataFrame::new_infer_height(vec![
        Column::new("i".into(), [Some(1i64), None, Some(3)]),
        Column::new("s".into(), [Some("a"), Some("b"), None]),
        Column::new("f".into(), [1.5f64, 2.5, 3.5]),
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
    let mut df =
        DataFrame::new_infer_height(vec![Column::new("x".into(), [1i64, 2])])
            .unwrap();
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
    let bad = || CString::new(vec![0xffu8]).unwrap();
    let every = Csv {
        null_values: vec![bad()],
        ..Default::default()
    };
    let msg = every.read_err(&path);
    assert!(msg.contains("null values"), "{:?}", msg);
    let named = Csv {
        named_nulls: vec![(cstr("x"), bad())],
        ..Default::default()
    };
    let msg = named.read_err(&path);
    assert!(msg.contains("null values"), "{:?}", msg);
    let renamed = Csv {
        new_columns: vec![bad()],
        ..Default::default()
    };
    let msg = renamed.read_err(&path);
    assert!(msg.contains("new column names"), "{:?}", msg);
}

#[test]
fn a_named_null_value_applies_to_its_column_only() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "n.csv", b"a,b\n1,-\n-,x\n3,y\n");
    let csv = Csv {
        named_nulls: vec![(cstr("a"), cstr("-"))],
        ..Default::default()
    };
    let df = csv.read(&path);
    assert_eq!(df.column("a").unwrap().dtype(), &DataType::Int64);
    assert_eq!(df.column("a").unwrap().null_count(), 1);
    assert_eq!(strings(&df, "b"), ["-", "x", "y"]);
    assert!(df.equals_missing(&csv.scan_collect(&path)));

    let absent = Csv {
        named_nulls: vec![(cstr("zzz"), cstr("-"))],
        ..Default::default()
    };
    let msg = absent.read_err(&path);
    assert!(msg.contains("unable to find column \"zzz\""), "{:?}", msg);

    let both = Csv {
        null_values: vec![cstr("x")],
        named_nulls: vec![(cstr("a"), cstr("-"))],
        ..Default::default()
    };
    let msg = both.read_err(&path);
    assert!(
        msg.contains("both for every column and by column"),
        "{:?}",
        msg
    );
}

#[test]
fn new_columns_rename_before_the_other_keywords_name_columns() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "r.csv", b"a,b,c\n1,-,x\n2,3,y\n");
    let csv = Csv {
        new_columns: vec![cstr("p"), cstr("q")],
        named_nulls: vec![(cstr("q"), cstr("-"))],
        overrides: vec![(
            cstr("q"),
            dtype(CompatDTypeTag::Float64, CompatTimeUnit::None),
        )],
        columns: vec![cstr("q"), cstr("p")],
        ..Default::default()
    };
    let df = csv.read(&path);
    assert_eq!(df.get_column_names(), ["p", "q"]);
    assert_eq!(df.column("q").unwrap().dtype(), &DataType::Float64);
    assert_eq!(df.column("q").unwrap().null_count(), 1);
    assert!(df.equals_missing(&csv.scan_collect(&path)));

    let missing = dir.path().join("missing.csv");
    let msg = csv.scan_err(&missing);
    assert!(msg.starts_with("cannot open file: "), "{:?}", msg);
    assert!(!msg.contains("missing.csv"), "{:?}", msg);
}

#[test]
fn a_selection_keeps_the_file_order_and_the_row_index() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "s.csv", b"a,b,c\n1,2,3\n4,5,6\n");
    let by_name = Csv {
        columns: vec![cstr("c"), cstr("a")],
        row_index_name: Some(cstr("i")),
        ..Default::default()
    };
    let by_index = Csv {
        projection: vec![2, 0],
        row_index_name: Some(cstr("i")),
        ..Default::default()
    };
    for csv in [&by_name, &by_index] {
        let df = csv.read(&path);
        assert_eq!(df.get_column_names(), ["i", "a", "c"]);
        assert!(df.equals_missing(&csv.scan_collect(&path)));
    }
    let both = Csv {
        columns: vec![cstr("a")],
        projection: vec![0],
        ..Default::default()
    };
    let msg = both.read_err(&path);
    assert!(msg.contains("both by name and by index"), "{:?}", msg);
}

#[test]
fn a_row_index_that_takes_a_column_name_is_refused_on_every_path() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "x.csv", b"a,b\n1,2\n");
    let expected =
        "duplicate: cannot add row_index with name 'a': column already exists in file.";
    let csv = Csv {
        row_index_name: Some(cstr("a")),
        ..Default::default()
    };
    assert_eq!(csv.read_err(&path), expected);
    assert_eq!(csv.read_outcome(&path).unwrap_err(), expected);
    assert_eq!(csv.scan_outcome(&path).unwrap_err(), expected);
    let renamed = Csv {
        row_index_name: Some(cstr("x")),
        new_columns: vec![cstr("x")],
        ..Default::default()
    };
    let expected =
        "duplicate: cannot add row_index with name 'x': column already exists in file.";
    assert_eq!(renamed.read_err(&path), expected);
    assert_eq!(renamed.scan_err(&path), expected);
}

fn written(df: &mut DataFrame, options: CompatCsvWriteOptions) -> String {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("w.csv");
    let p = cstr(path.to_str().unwrap());
    let crlf = cstr("\r\n");
    let na = cstr("NA");
    let date = cstr("%d.%m.%Y");
    let status = dataframe_write_csv_with_options(
        df,
        p.as_ptr(),
        options,
        crlf.as_ptr(),
        na.as_ptr(),
        ptr::null(),
        date.as_ptr(),
        ptr::null(),
    );
    assert_eq!(status, 0, "{:?}", recorded_error());
    std::fs::read_to_string(&path).expect("read back")
}

#[test]
fn the_writer_applies_every_option() {
    let mut df = DataFrame::new_infer_height(vec![
        Column::new("s".into(), [Some("a;b"), None]),
        Column::new("f".into(), [Some(1.25f64), Some(1e-10)]),
        Column::new(
            "d".into(),
            [NaiveDate::from_ymd_opt(2024, 1, 2).unwrap(); 2],
        ),
    ])
    .unwrap();
    let options = CompatCsvWriteOptions {
        include_header: false,
        include_bom: true,
        separator: b';',
        quote_char: b'\'',
        quote_style: 2,
        decimal_comma: true,
        has_float_scientific: true,
        float_scientific: false,
        has_float_precision: true,
        float_precision: 3,
        batch_size: 1,
    };
    assert_eq!(
        written(&mut df, options),
        "\u{feff}'a;b';1,250;'02.01.2024'\r\nNA;0,000;'02.01.2024'\r\n"
    );
    let mut bad = options;
    bad.quote_style = 9;
    let dir = tempfile::tempdir().expect("tempdir");
    let p = cstr(dir.path().join("bad.csv").to_str().unwrap());
    let status = dataframe_write_csv_with_options(
        &mut df,
        p.as_ptr(),
        bad,
        ptr::null(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
    );
    assert_eq!(status, 4);
    assert_eq!(recorded_error().as_deref(), Some("unknown quote style 9"));
}

fn strings(df: &DataFrame, name: &str) -> Vec<String> {
    df.column(name)
        .unwrap()
        .str()
        .unwrap()
        .iter()
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
