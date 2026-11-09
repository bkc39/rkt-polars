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
            "escaped-pair.csv",
            b"a\n1\n\"12\"\"",
            "a",
            plain(T::Int64),
            "\"12\"\"",
            "i64",
        ),
        case(
            "three-quotes.csv",
            b"a\n1\n\"\"\"",
            "a",
            plain(T::Int64),
            "\"\"\"",
            "i64",
        ),
        case(
            "reopened.csv",
            b"a\n1\n\"1\"2\"",
            "a",
            plain(T::Int64),
            "\"1\"2\"",
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
        assert!(
            msg.contains("The current offset in the file is "),
            "{} {}: {:?}",
            self.name,
            how,
            msg
        );
        assert_no_hint(&msg, &format!("{} {}", self.name, how));
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

const HINT: &str = "You might want to try:";

fn assert_no_hint(msg: &str, label: &str) {
    assert!(!msg.contains(HINT), "{}: {:?}", label, msg);
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
fn an_inferred_column_refuses_an_unclosed_quote_past_inference() {
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
    let schema = || {
        Some(Arc::new(Schema::from_iter([Field::new(
            "a".into(),
            DataType::Decimal(10, 2),
        )])))
    };
    for (name, text, field) in [
        ("decimal.csv", &b"a\n1.5\n\""[..], "\""),
        ("digits.csv", &b"a\n1.5\n\"1.55"[..], "\"1.55"),
    ] {
        let path = write(dir.path(), name, text);
        let read = |ignore_errors: bool| {
            CsvReadOptions::default()
                .with_has_header(true)
                .with_ignore_errors(ignore_errors)
                .with_schema_overwrite(schema())
                .try_into_reader_with_file_path(Some(path.clone()))
                .and_then(|reader| reader.finish())
        };
        let scan = |ignore_errors: bool| {
            LazyCsvReader::new(path.to_str().unwrap().into())
                .with_has_header(true)
                .with_ignore_errors(ignore_errors)
                .with_dtype_overwrite(schema())
                .finish()
                .and_then(|lf| lf.collect())
        };
        let expected = format!(
            "could not parse `{}` as dtype `decimal[10,2]` at column 'a'",
            field
        );
        for (how, outcome) in [("read", read(false)), ("scan", scan(false))] {
            let msg = outcome.expect_err("a parse error").to_string();
            assert!(msg.starts_with(&expected), "{} {}: {:?}", name, how, msg);
        }
        for (how, outcome) in [("read", read(true)), ("scan", scan(true))] {
            let df =
                outcome.unwrap_or_else(|e| panic!("{} {}: {}", name, how, e));
            assert_eq!(df.height(), 2, "{} {}", name, how);
            assert_eq!(
                df.column("a").unwrap().null_count(),
                1,
                "{} {}",
                name,
                how
            );
        }
    }
}

#[test]
fn a_categorical_column_refuses_an_unclosed_quote_as_a_string_column_does() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    for (i, field) in ["\"ab", "\"ab\"\"", "\"\"\"", "\"a\"b\""]
        .iter()
        .enumerate()
    {
        let text = format!("a\nx\n{}", field);
        let path =
            write(dir.path(), &format!("cat-{}.csv", i), text.as_bytes());
        for (tag, name) in [(T::String, "str"), (T::Categorical, "cat")] {
            let csv = Csv {
                overrides: vec![(bytes_of("a"), plain(tag))],
                ..Default::default()
            };
            for (how, outcome) in outcomes(&csv, &path)
                .into_iter()
                .chain(outcomes(&ignoring_errors(&csv), &path))
            {
                let msg = outcome.err().unwrap_or_else(|| {
                    panic!("{} {} {}: read", name, field, how)
                });
                let cause =
                    format!("Field `{}` is not properly escaped.", field);
                assert!(
                    msg.starts_with(&format!(
                        "could not parse `{}` as dtype",
                        field
                    )) && msg.contains(&cause),
                    "{} {} {}: {:?}",
                    name,
                    field,
                    how,
                    msg
                );
                assert_no_hint(&msg, &format!("{} {} {}", name, field, how));
            }
        }
    }
}

#[test]
fn a_time_column_refuses_an_unclosed_quote_as_a_string_even_ignoring_errors() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let path = write(dir.path(), "time.csv", b"a\n10:00:00\n\"10:00:001");
    let csv = Csv {
        overrides: vec![(bytes_of("a"), plain(T::Time))],
        ..Default::default()
    };
    for (how, outcome) in outcomes(&csv, &path)
        .into_iter()
        .chain(outcomes(&ignoring_errors(&csv), &path))
    {
        let msg = outcome.err().unwrap_or_else(|| panic!("{}: read", how));
        assert!(
            msg.starts_with("could not parse `\"10:00:001` as dtype `str`")
                && msg.contains("Field `\"10:00:001` is not properly escaped."),
            "{}: {:?}",
            how,
            msg
        );
        assert_no_hint(&msg, how);
    }
}

#[test]
fn a_null_marker_is_not_matched_inside_an_unclosed_quote() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures: [(&'static str, &'static [u8], &str, &'static str); 2] = [
        ("prefix.csv", b"a\n1\n\"NA", "N", "\"NA"),
        ("quotes.csv", b"a\n1\n\"\"\"", "\"", "\"\"\""),
    ];
    for (name, text, marker, field) in fixtures {
        let path = write(dir.path(), name, text);
        let csv = Csv {
            overrides: vec![(bytes_of("a"), plain(T::Int64))],
            null_values: vec![bytes_of(marker)],
            ..Default::default()
        };
        let case = Case {
            name,
            text,
            column: "a",
            dtype: plain(T::Int64),
            field,
            polars_dtype: "i64",
        };
        for (how, outcome) in [
            ("read", csv.read_outcome(&path)),
            ("scan", csv.scan_outcome(&path)),
        ] {
            case.assert_refused(&path, outcome, how);
        }
        let ignoring = ignoring_errors(&csv);
        for (how, outcome) in [
            ("read", ignoring.read_outcome(&path)),
            ("scan", ignoring.scan_outcome(&path)),
        ] {
            case.assert_last_is_null(outcome, how);
        }
    }
}

#[test]
fn a_header_with_an_unclosed_quote_is_refused_even_ignoring_errors() {
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures: [(&str, &[u8]); 3] = [
        ("bare.csv", b"x,\"ab"),
        ("newline.csv", b"x,\"ab\n"),
        ("rows.csv", b"x,\"ab\n1,2\n"),
    ];
    for (name, text) in fixtures {
        let path = write(dir.path(), name, text);
        for csv in [Csv::default(), ignoring_errors(&Csv::default())] {
            for (how, outcome) in [
                ("read", csv.read_outcome(&path)),
                ("scan", csv.scan_outcome(&path)),
            ] {
                let msg = outcome
                    .err()
                    .unwrap_or_else(|| panic!("{} {}: read", name, how));
                assert!(
                    msg.contains("Column name `\"ab")
                        && msg.contains("is not properly escaped."),
                    "{} {}: {:?}",
                    name,
                    how,
                    msg
                );
            }
        }
    }
}

#[test]
fn a_quote_char_other_than_the_double_quote_closes_by_the_same_rule() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let mut csv = Csv {
        overrides: vec![(bytes_of("a"), plain(T::Int64))],
        ..Default::default()
    };
    csv.options.quote_char = b'\'';
    let case = Case {
        name: "open.csv",
        text: b"a\n1\n'12",
        column: "a",
        dtype: plain(T::Int64),
        field: "'12",
        polars_dtype: "i64",
    };
    let open = write(dir.path(), case.name, case.text);
    for (how, outcome) in outcomes(&csv, &open) {
        case.assert_refused(&open, outcome, how);
    }
    let closed = write(dir.path(), "closed.csv", b"a\n1\n'12'");
    for (how, outcome) in outcomes(&csv, &closed) {
        let df = outcome.unwrap_or_else(|e| panic!("{}: {}", how, e));
        let column = df.column("a").unwrap();
        assert_eq!(column.get(1).unwrap(), AnyValue::Int64(12), "{}", how);
    }
    for (tag, polars_dtype) in [(T::Int64, "i64"), (T::String, "str")] {
        let odd = Case {
            name: "odd.csv",
            text: b"a\n1\n'12''",
            column: "a",
            dtype: plain(tag),
            field: "'12''",
            polars_dtype,
        };
        let path = write(dir.path(), odd.name, odd.text);
        let typed = Csv {
            overrides: vec![(bytes_of("a"), plain(tag))],
            ..csv.clone()
        };
        for (how, outcome) in outcomes(&typed, &path) {
            odd.assert_refused(&path, outcome, how);
        }
    }
    let strings = Csv {
        overrides: vec![(bytes_of("a"), plain(T::String))],
        ..csv.clone()
    };
    let inner = write(dir.path(), "inner.csv", b"a\nx\n'a\"b'");
    for (how, outcome) in outcomes(&strings, &inner) {
        let df = outcome.unwrap_or_else(|e| panic!("{}: {}", how, e));
        let column = df.column("a").unwrap();
        assert_eq!(column.get(1).unwrap(), AnyValue::String("a\"b"), "{}", how);
    }
}

#[test]
fn a_closed_field_with_bytes_after_its_close_reads_as_in_0_55() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let typed = |tag| Csv {
        overrides: vec![(bytes_of("a"), plain(tag))],
        ..Default::default()
    };
    let path = write(dir.path(), "trailing.csv", b"a,b\n\"ab\"c,1\n");
    let categorical = typed(T::Categorical);
    for (how, outcome) in outcomes(&categorical, &path)
        .into_iter()
        .chain(outcomes(&ignoring_errors(&categorical), &path))
    {
        let df = outcome.unwrap_or_else(|e| panic!("cat {}: {}", how, e));
        let strings = df.column("a").unwrap().cast(&DataType::String).unwrap();
        assert_eq!(strings.str().unwrap().get(0), Some("ab"), "cat {}", how);
    }
    let string = typed(T::String);
    for (how, outcome) in outcomes(&string, &path)
        .into_iter()
        .chain(outcomes(&ignoring_errors(&string), &path))
    {
        let msg = outcome.err().unwrap_or_else(|| panic!("str {}: read", how));
        assert!(
            msg.starts_with("could not parse `\"ab\"c` as dtype `str`")
                && msg.contains("Field `\"ab\"c` is not properly escaped."),
            "str {}: {:?}",
            how,
            msg
        );
    }
    let path = write(dir.path(), "trailing-int.csv", b"a,b\n\"12\"3,1\n");
    let int = typed(T::Int64);
    for (how, outcome) in outcomes(&int, &path) {
        let msg = outcome.err().unwrap_or_else(|| panic!("i64 {}: read", how));
        assert!(
            msg.starts_with("could not parse `\"12\"3` as dtype `i64`")
                && msg.contains(
                    "invalid primitive value found during CSV parsing"
                ),
            "i64 {}: {:?}",
            how,
            msg
        );
    }
    for (how, outcome) in outcomes(&ignoring_errors(&int), &path) {
        let df = outcome.unwrap_or_else(|e| panic!("i64 {}: {}", how, e));
        assert!(
            df.column("a").unwrap().get(0).unwrap().is_null(),
            "i64 {}",
            how
        );
    }
}

#[test]
fn a_null_marker_never_matches_an_unclosed_field() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures: [(&str, &[u8], &str); 2] = [
        ("marker.csv", b"a,b\n1,\"NA", "\"NA"),
        ("quote.csv", b"a,b\n1,\"", "\""),
    ];
    for (name, text, field) in fixtures {
        let path = write(dir.path(), name, text);
        for (tag, polars_dtype) in [(T::String, "str"), (T::Int64, "i64")] {
            let csv = Csv {
                overrides: vec![(bytes_of("b"), plain(tag))],
                null_values: vec![bytes_of(field)],
                ..Default::default()
            };
            let mut head = csv.clone();
            head.options.has_n_rows = true;
            head.options.n_rows = 10;
            let ignoring = ignoring_errors(&csv);
            let mut refused = vec![
                ("read", csv.read_outcome(&path)),
                ("scan", csv.scan_outcome(&path)),
                ("glob", csv.read_outcome(&one_file_pattern(&path))),
                ("n_rows read", head.read_outcome(&path)),
                ("n_rows scan", head.scan_outcome(&path)),
            ];
            let ignored = vec![
                ("ignoring read", ignoring.read_outcome(&path)),
                ("ignoring scan", ignoring.scan_outcome(&path)),
            ];
            if tag == T::String {
                refused.extend(ignored);
            } else {
                for (how, outcome) in ignored {
                    let df = outcome
                        .unwrap_or_else(|e| panic!("{} {}: {}", name, how, e));
                    assert!(
                        df.column("b").unwrap().get(0).unwrap().is_null(),
                        "{} {}",
                        name,
                        how
                    );
                }
            }
            let case = Case {
                name,
                text,
                column: "b",
                dtype: plain(tag),
                field,
                polars_dtype,
            };
            for (how, outcome) in refused {
                case.assert_refused(&path, outcome, how);
            }
        }
    }
}

#[test]
fn an_ordinary_bad_value_keeps_the_hint() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures: [(&str, &[u8], CompatDTypeTag, &str); 3] = [
        ("bare.csv", b"a\ny", T::Int64, "y"),
        ("quoted.csv", b"a\n1\n\"y\"", T::Int64, "\"y\""),
        ("trailing.csv", b"a,b\n\"ab\"c,1\n", T::String, "\"ab\"c"),
    ];
    for (name, text, tag, field) in fixtures {
        let path = write(dir.path(), name, text);
        let csv = Csv {
            overrides: vec![(bytes_of("a"), plain(tag))],
            ..Default::default()
        };
        for (how, outcome) in outcomes(&csv, &path) {
            let msg = outcome
                .err()
                .unwrap_or_else(|| panic!("{} {}: read", name, how));
            assert!(
                msg.starts_with(&format!(
                    "could not parse `{}` as dtype",
                    field
                )) && msg.contains(HINT)
                    && msg.contains(&format!(
                        "adding `{}` to the `null_values` list",
                        field
                    )),
                "{} {}: {:?}",
                name,
                how,
                msg
            );
        }
    }
}

#[test]
fn a_closed_quoted_field_equal_to_a_marker_is_null() {
    use CompatDTypeTag as T;
    let dir = tempfile::tempdir().expect("tempdir");
    let fixtures: [(&str, &[u8], &str); 2] = [
        ("na.csv", b"a\n\"NA\"\n1\n", "NA"),
        ("pair.csv", b"a\n\"N\"\"A\"\n1\n", "N\"\"A"),
    ];
    for (name, text, marker) in fixtures {
        let path = write(dir.path(), name, text);
        let gz = write(dir.path(), &format!("{}.gz", name), &gzip_bytes(text));
        for overrides in [vec![], vec![(bytes_of("a"), plain(T::Int64))]] {
            let csv = Csv {
                overrides,
                null_values: vec![bytes_of(marker)],
                ..Default::default()
            };
            let mut head = csv.clone();
            head.options.has_n_rows = true;
            head.options.n_rows = 10;
            let mut commented = csv.clone();
            commented.comment_prefix = Some(bytes_of("#"));
            for (how, outcome) in [
                ("read", csv.read_outcome(&path)),
                ("scan", csv.scan_outcome(&path)),
                ("glob", csv.read_outcome(&one_file_pattern(&path))),
                ("gzip read", csv.read_outcome(&gz)),
                ("gzip scan", csv.scan_outcome(&gz)),
                ("n_rows read", head.read_outcome(&path)),
                ("n_rows scan", head.scan_outcome(&path)),
                ("commented read", commented.read_outcome(&path)),
                ("commented scan", commented.scan_outcome(&path)),
            ] {
                let df = outcome
                    .unwrap_or_else(|e| panic!("{} {}: {}", name, how, e));
                let column = df.column("a").unwrap();
                assert_eq!(
                    column.dtype(),
                    &DataType::Int64,
                    "{} {}",
                    name,
                    how
                );
                assert_eq!(
                    (0..column.len())
                        .map(|i| column.get(i).unwrap().extract::<i64>())
                        .collect::<Vec<_>>(),
                    [None, Some(1)],
                    "{} {}",
                    name,
                    how
                );
            }
        }
    }
}
