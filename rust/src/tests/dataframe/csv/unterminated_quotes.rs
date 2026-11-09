use super::*;

struct Case {
    name: &'static str,
    text: &'static [u8],
    column: &'static str,
    dtype: CompatDType,
    field: &'static str,
    polars_dtype: &'static str,
}

fn plain(tag: CompatDTypeTag) -> CompatDType {
    dtype(tag, CompatTimeUnit::None)
}

fn cases() -> Vec<Case> {
    use CompatDTypeTag as T;
    let case = |name, text, column, dtype, field, polars_dtype| Case {
        name,
        text,
        column,
        dtype,
        field,
        polars_dtype,
    };
    vec![
        case("i64.csv", b"a\n1\n\"", "a", plain(T::Int64), "\"", "i64"),
        case("i32.csv", b"a\n1\n\"", "a", plain(T::Int32), "\"", "i32"),
        case("u8.csv", b"a\n1\n\"", "a", plain(T::UInt8), "\"", "u8"),
        case("f32.csv", b"a\n1\n\"", "a", plain(T::Float32), "\"", "f32"),
        case("f64.csv", b"a\n1\n\"", "a", plain(T::Float64), "\"", "f64"),
        case(
            "bool.csv",
            b"a\ntrue\n\"",
            "a",
            plain(T::Boolean),
            "\"",
            "bool",
        ),
        case(
            "crlf.csv",
            b"a\r\n1\r\n\"\r",
            "a",
            plain(T::Int64),
            "\"",
            "i64",
        ),
        case(
            "second.csv",
            b"a,b\n1,2\n3,\"",
            "b",
            plain(T::Int64),
            "\"",
            "i64",
        ),
        case(
            "digits.csv",
            b"a\n1\n\"12",
            "a",
            plain(T::Int64),
            "\"12",
            "i64",
        ),
        case(
            "digit.csv",
            b"a\n1\n\"2",
            "a",
            plain(T::Int64),
            "\"2",
            "i64",
        ),
        case(
            "t.csv",
            b"a\ntrue\n\"t",
            "a",
            plain(T::Boolean),
            "\"t",
            "bool",
        ),
        case(
            "date.csv",
            b"a\n2020-01-01\n\"2020-01-022",
            "a",
            plain(T::Date),
            "\"2020-01-022",
            "date",
        ),
        case(
            "datetime.csv",
            b"a\n2020-01-01 00:00:00\n\"2020-01-01 00:00:001",
            "a",
            dtype(T::Datetime, CompatTimeUnit::Microseconds),
            "\"2020-01-01 00:00:001",
            "datetime[\u{3bc}s]",
        ),
    ]
}

impl Case {
    fn csv(&self) -> Csv {
        Csv {
            overrides: vec![(bytes_of(self.column), self.dtype)],
            ..Default::default()
        }
    }

    fn assert_refused(&self, path: &Path, outcome: Outcome, how: &str) {
        let msg = outcome.err().unwrap_or_else(|| {
            panic!("{} {}: {:?} read", self.name, how, path)
        });
        let index = if self.column == "a" { 1 } else { 2 };
        let expected = format!(
            "could not parse `{}` as dtype `{}` at column '{}' (column number {})",
            self.field, self.polars_dtype, self.column, index
        );
        assert!(
            msg.starts_with(&expected),
            "{} {}: {:?}",
            self.name,
            how,
            msg
        );
        let cause = format!("Field `{}` is not properly escaped.", self.field);
        assert!(msg.contains(&cause), "{} {}: {:?}", self.name, how, msg);
    }

    fn assert_last_is_null(&self, outcome: Outcome, how: &str) {
        let df =
            outcome.unwrap_or_else(|e| panic!("{} {}: {}", self.name, how, e));
        assert_eq!(df.height(), 2, "{} {}", self.name, how);
        let column = df.column(self.column).unwrap();
        assert_eq!(column.null_count(), 1, "{} {}: {:?}", self.name, how, df);
        assert!(
            column.get(1).unwrap().is_null(),
            "{} {}: {:?}",
            self.name,
            how,
            df
        );
    }
}

fn outcomes(csv: &Csv, path: &Path) -> Vec<(&'static str, Outcome)> {
    let mut head = csv.clone();
    head.options.has_n_rows = true;
    head.options.n_rows = 10;
    let mut commented = csv.clone();
    commented.comment_prefix = Some(bytes_of("#"));
    let mut nulls = csv.clone();
    nulls.null_values = vec![bytes_of("x")];
    vec![
        ("read", csv.read_outcome(path)),
        ("scan", csv.scan_outcome(path)),
        ("glob", csv.read_outcome(&one_file_pattern(path))),
        ("n_rows read", head.read_outcome(path)),
        ("n_rows scan", head.scan_outcome(path)),
        ("commented read", commented.read_outcome(path)),
        ("commented scan", commented.scan_outcome(path)),
        ("null_values read", nulls.read_outcome(path)),
        ("null_values scan", nulls.scan_outcome(path)),
    ]
}

fn ignoring_errors(csv: &Csv) -> Csv {
    let mut csv = csv.clone();
    csv.options.ignore_errors = true;
    csv
}

#[test]
fn an_unclosed_quote_in_the_last_field_is_a_parse_error_on_every_path() {
    let dir = tempfile::tempdir().expect("tempdir");
    for case in cases() {
        let path = write(dir.path(), case.name, case.text);
        for (how, outcome) in outcomes(&case.csv(), &path) {
            case.assert_refused(&path, outcome, how);
        }
        let gz = write(
            dir.path(),
            &format!("{}.gz", case.name),
            &gzip_bytes(case.text),
        );
        for (how, outcome) in [
            ("gzip read", case.csv().read_outcome(&gz)),
            ("gzip scan", case.csv().scan_outcome(&gz)),
        ] {
            case.assert_refused(&gz, outcome, how);
        }
    }
}

#[test]
fn ignore_errors_reads_an_unclosed_quote_as_a_null() {
    let dir = tempfile::tempdir().expect("tempdir");
    for case in cases() {
        let path = write(dir.path(), case.name, case.text);
        for (how, outcome) in outcomes(&ignoring_errors(&case.csv()), &path) {
            case.assert_last_is_null(outcome, how);
        }
    }
}

#[test]
fn an_inferred_column_reads_the_unclosed_quote_as_far_as_inference_saw() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "late.csv", b"a\n1\n2\n\"");
    let mut csv = Csv::default();
    csv.options.infer_schema_length = 1;
    csv.options.has_infer_schema_length = true;
    for (how, outcome) in outcomes(&csv, &path) {
        let msg = outcome.err().unwrap_or_else(|| panic!("{} read", how));
        assert!(
            msg.starts_with(
                "could not parse `\"` as dtype `i64` at column 'a'"
            ),
            "{}: {:?}",
            how,
            msg
        );
    }
}

#[test]
fn a_closed_quoted_last_field_still_reads() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures: [(&str, &[u8], CompatDType, &[Option<&str>]); 6] = [
        (
            "empty.csv",
            b"a\n1\n\"\"",
            plain(T::Int64),
            &[Some("1"), None],
        ),
        (
            "value.csv",
            b"a\n1\n\"12\"",
            plain(T::Int64),
            &[Some("1"), Some("12")],
        ),
        (
            "crlf.csv",
            b"a\r\n1\r\n\"12\"\r",
            plain(T::Int64),
            &[Some("1"), Some("12")],
        ),
        (
            "float.csv",
            b"a\n1\n\"2.5\"",
            plain(T::Float64),
            &[Some("1.0"), Some("2.5")],
        ),
        (
            "bool.csv",
            b"a\ntrue\n\"false\"",
            plain(T::Boolean),
            &[Some("true"), Some("false")],
        ),
        (
            "date.csv",
            b"a\n2020-01-01\n\"2020-01-02\"",
            plain(T::Date),
            &[Some("2020-01-01"), Some("2020-01-02")],
        ),
    ];
    for (name, text, dtype, expected) in fixtures {
        let path = write(dir.path(), name, text);
        let csv = Csv {
            overrides: vec![(bytes_of("a"), dtype)],
            ..Default::default()
        };
        for (how, outcome) in outcomes(&csv, &path)
            .into_iter()
            .chain(outcomes(&ignoring_errors(&csv), &path))
        {
            let df =
                outcome.unwrap_or_else(|e| panic!("{} {}: {}", name, how, e));
            let strings =
                df.column("a").unwrap().cast(&DataType::String).unwrap();
            let strings = strings.str().unwrap();
            let got: Vec<Option<String>> = (0..strings.len())
                .map(|i| strings.get(i).map(str::to_owned))
                .collect();
            let expected: Vec<Option<String>> =
                expected.iter().map(|v| v.map(str::to_owned)).collect();
            assert_eq!(got, expected, "{} {}", name, how);
        }
    }
}

#[test]
fn a_decimal_column_refuses_an_unclosed_quote_or_nulls_it() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "decimal.csv", b"a\n1.5\n\"");
    let read = |ignore_errors: bool| {
        CsvReadOptions::default()
            .with_has_header(true)
            .with_ignore_errors(ignore_errors)
            .with_schema_overwrite(Some(Arc::new(Schema::from_iter([
                Field::new("a".into(), DataType::Decimal(10, 2)),
            ]))))
            .try_into_reader_with_file_path(Some(path.clone()))
            .and_then(|reader| reader.finish())
    };
    let msg = read(false).expect_err("a parse error").to_string();
    assert!(
        msg.starts_with(
            "could not parse `\"` as dtype `decimal[10,2]` at column 'a'"
        ),
        "{:?}",
        msg
    );
    let df = read(true).expect("a null");
    assert_eq!(df.column("a").unwrap().null_count(), 1);
}

#[test]
fn a_categorical_column_refuses_an_unclosed_quote_as_a_string_column_does() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "cat.csv", b"a\nx\n\"ab");
    for tag in [T::String, T::Categorical] {
        let csv = Csv {
            overrides: vec![(bytes_of("a"), plain(tag))],
            ..Default::default()
        };
        for (how, outcome) in outcomes(&csv, &path)
            .into_iter()
            .chain(outcomes(&ignoring_errors(&csv), &path))
        {
            let msg = outcome
                .err()
                .unwrap_or_else(|| panic!("{:?} {}: read", tag as i32, how));
            assert!(
                msg.starts_with("could not parse `\"ab` as dtype")
                    && msg.contains("Field `\"ab` is not properly escaped."),
                "{:?} {}: {:?}",
                tag as i32,
                how,
                msg
            );
        }
    }
}
