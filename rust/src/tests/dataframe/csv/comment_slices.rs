use super::*;
use std::ops::Range;

const LATE_NA_ROWS: usize = 110_000;
const LATE_NA_BYTES: Range<usize> = 900 * 1024..1200 * 1024;
const FIRST_BATCH_BYTES: usize = 64 * 1024;
const LAW_FIXTURE_BYTES: usize = 200 * 1024;
const LONG_LAW_FIXTURE_BYTES: usize = 480 * 1024;
const BAD_ROW: &str = "oops,v,extra";
const LARGEST_BATCH_BYTES: usize = 512 * 1024;

fn commented_every_ten(text: &str) -> String {
    text.lines()
        .enumerate()
        .map(|(i, line)| match i % 10 {
            0 if i > 0 => format!("# before line {}\n{}\n", i, line),
            _ => format!("{}\n", line),
        })
        .collect()
}

fn commented_late_na() -> String {
    commented_every_ten(&int_column_with_na_after(LATE_NA_ROWS))
}

fn commented_head(n: usize) -> Csv {
    let mut csv = commented_csv("#");
    csv.options.has_n_rows = true;
    csv.options.n_rows = n;
    csv
}

fn assert_first_row_only(outcomes: [Outcome; 2]) {
    for outcome in outcomes {
        let df = outcome.expect("the slice stops before the NA");
        assert_eq!(df.height(), 1);
        assert_eq!(read_i64(&df, "id"), [0]);
    }
}

#[test]
fn a_commented_n_rows_read_stops_at_the_first_batch_past_the_slice() {
    let dir = tempfile::tempdir().expect("tempdir");
    let text = commented_late_na();
    assert!(LATE_NA_BYTES.contains(&text.len()), "{}", text.len());
    let path = write(dir.path(), "late-na.csv", text.as_bytes());
    let csv = commented_head(1);
    assert_first_row_only([csv.read_outcome(&path), csv.scan_outcome(&path)]);
}

#[test]
fn a_commented_gzip_n_rows_read_decompresses_only_a_prefix() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut cut = gzip_bytes(commented_late_na().replace("NA", "7").as_bytes());
    cut.truncate(cut.len() - 64);
    let path = write(dir.path(), "cut.csv.gz", &cut);
    assert!(commented_csv("#").scan_outcome(&path).is_err());
    let csv = commented_head(1);
    assert_first_row_only([csv.read_outcome(&path), csv.scan_outcome(&path)]);
}

#[test]
fn ignore_errors_with_a_comment_prefix_reads_the_rows_a_full_read_gives() {
    let dir = tempfile::tempdir().expect("tempdir");
    let stray =
        write(dir.path(), "stray.csv", b"a,b\n1,5\"\n2,6\n# note\n3,7\n");
    let rows: String = (0..20_000).map(|i| format!("v{}\n", i)).collect();
    let unended = write(
        dir.path(),
        "unended.csv",
        format!("a\n{}x#y", rows).as_bytes(),
    );
    for (path, n) in [(&stray, 2), (&unended, 20_001)] {
        let mut whole = commented_csv("#");
        whole.options.ignore_errors = true;
        let expected = whole.scan_collect(path).head(Some(n));
        assert_eq!(expected.height(), n, "{:?}", path);
        let mut csv = commented_head(n);
        csv.options.ignore_errors = true;
        for got in [csv.read_outcome(path), csv.scan_outcome(path)] {
            assert!(
                same_outcome(&got, &Ok(expected.clone())),
                "{:?}: {:?}",
                path,
                got
            );
        }
    }
}

#[test]
fn a_final_line_without_a_newline_reads_as_the_terminated_file_does() {
    let dir = tempfile::tempdir().expect("tempdir");
    let padding: String = (0..20_000).map(|i| format!("v{}\n", i)).collect();
    let quoted = "1\n\"x\n#y\"";
    for (prefix, rows, last, values) in [
        ("#", padding.as_str(), "# the end", &[][..]),
        ("#", padding.as_str(), "#", &[]),
        ("#", padding.as_str(), "x#y", &["x#y"]),
        ("//", padding.as_str(), "x//y", &["x//y"]),
        ("//", padding.as_str(), "// the end", &[]),
        ("#", padding.as_str(), quoted, &["1", "x\n#y"]),
        ("#", "", "x#y", &["x#y"]),
        ("//", "", "x//y", &["x//y"]),
        ("#", "", quoted, &["1", "x\n#y"]),
    ] {
        let csv = commented_csv(prefix);
        let ended = write(
            dir.path(),
            "ended.csv",
            format!("a\n{}{}\n", rows, last).as_bytes(),
        );
        let reference = csv.scan_collect(&ended);
        let expected: Vec<String> = (0..rows.lines().count())
            .map(|i| format!("v{}", i))
            .chain(values.iter().map(|v| v.to_string()))
            .collect();
        assert_eq!(
            strings(&reference, "a"),
            expected,
            "the terminated file ending in {:?}",
            last
        );
        let path = write(
            dir.path(),
            "end.csv",
            format!("a\n{}{}", rows, last).as_bytes(),
        );
        let lf = || csv.scan(&path);
        let height = reference.height();
        let mut head = csv.clone();
        head.options.has_n_rows = true;
        head.options.n_rows = height;
        for (read, got, expected) in [
            ("a read", csv.read_outcome(&path), reference.clone()),
            ("a whole scan", csv.scan_outcome(&path), reference.clone()),
            (
                "a tail",
                lf().tail(5).collect().map_err(|e| e.to_string()),
                reference.tail(Some(5)),
            ),
            (
                "a slice",
                lf().slice(height as i64 - 2, 5)
                    .collect()
                    .map_err(|e| e.to_string()),
                reference.slice(height as i64 - 2, 5),
            ),
            (
                "an n-rows read",
                head.read_outcome(&path),
                reference.clone(),
            ),
        ] {
            assert!(
                same_outcome(&got, &Ok(expected)),
                "{} of a file ending in {:?} after {} rows: {:?}",
                read,
                last,
                height,
                got.map(|df| df.shape())
            );
        }
    }
}

fn fast_count(text: &str, prefix: &str) -> Result<usize, String> {
    let comment_prefix = CommentPrefix::new_from_str(prefix);
    polars::io::csv::read::count_rows_from_slice_par(
        polars_buffer::Buffer::from_vec(text.as_bytes().to_vec()),
        Some(b'"'),
        Some(&comment_prefix),
        b'\n',
        true,
        0,
        0,
        0,
        false,
    )
    .map_err(|e| e.to_string())
}

#[test]
fn the_fast_count_counts_a_final_line_as_the_full_read_does() {
    let dir = tempfile::tempdir().expect("tempdir");
    let padding: String = (0..200_000).map(|i| format!("v{}\n", i)).collect();
    assert!(padding.len() > 2 * LARGEST_BATCH_BYTES);
    for (prefix, rows, last, last_rows) in [
        ("#", "", "\"x\n#y\"", 1),
        ("#", "", "1\n\"x\n#y\"", 2),
        ("#", "", "x#y", 1),
        ("#", "", "# c", 0),
        ("#", "", "# c\n# d", 0),
        ("//", "", "x//y", 1),
        ("#", padding.as_str(), "\"x\n#y\"", 1),
        ("#", padding.as_str(), "1\n\"x\n#y\"", 2),
        ("#", padding.as_str(), "# c", 0),
        ("//", padding.as_str(), "// c\nx//y", 1),
    ] {
        let text = format!("a\n{}{}", rows, last);
        let path = write(dir.path(), "count.csv", text.as_bytes());
        let height = rows.lines().count() + last_rows;
        let full = commented_csv(prefix)
            .scan_outcome(&path)
            .map(|df| df.height());
        assert_eq!(
            (full, fast_count(&text, prefix)),
            (Ok(height), Ok(height)),
            "the full read and the fast count of a file ending in {:?}",
            last
        );
    }
}

#[test]
fn the_fast_count_reads_a_chunk_that_starts_inside_a_quoted_field() {
    let dir = tempfile::tempdir().expect("tempdir");
    let before: String =
        (0..47_662).map(|i| format!("p{:07},1\n", i)).collect();
    let field = format!("\"{}\n#y\",1\n", "x".repeat(20));
    let inner_newline = before.len() + 1 + 20;
    assert!(
        before.len() < LARGEST_BATCH_BYTES
            && LARGEST_BATCH_BYTES <= inner_newline
    );
    let after: String = (0..50_000).map(|i| format!("t{},2\n", i)).collect();
    let text = format!("a,b\n{}{}{}", before, field, after);
    let path = write(dir.path(), "straddle.csv", text.as_bytes());
    let full = commented_csv("#").scan_outcome(&path).map(|df| df.height());
    assert_eq!(
        (full, fast_count(&text, "#")),
        (Ok(97_663), Ok(97_663)),
        "a quoted field whose second line starts with the prefix, across a chunk boundary"
    );
}

#[test]
fn a_commented_read_is_the_scan_beside_a_quote_in_a_comment() {
    let dir = tempfile::tempdir().expect("tempdir");
    let stray: String = (0..8_000)
        .map(|i| format!("r{},v{}\n", i, i % 7))
        .chain([format!("p1,a\"b\np2,\"x\n{}\"\n# \"\n", "y".repeat(40_000))])
        .chain((0..20_000).map(|i| format!("s{},v{}\n", i, i % 7)))
        .collect();
    let quoted: String = (0..100_000)
        .map(|i| match i {
            50_000 => format!("# it\"s\n{},y\n", i),
            _ => format!("{},y\n", i),
        })
        .collect();
    let numbered = |range: std::ops::Range<usize>| -> Vec<String> {
        range.map(|i| i.to_string()).collect()
    };
    let stray_names: Vec<String> = (0..8_000)
        .map(|i| format!("r{}", i))
        .chain(["p1".to_string(), "p2".to_string()])
        .chain((0..20_000).map(|i| format!("s{}", i)))
        .collect();
    for (name, text, column_a) in [
        ("f8000.csv", format!("a,b\n{}", stray), stray_names),
        (
            "small.csv",
            "a,b\n1,x\n# it\"s\n2,y\n3,z\n".to_string(),
            numbered(1..4),
        ),
        (
            "quoted.csv",
            format!("a,b\n{}", quoted),
            numbered(0..100_000),
        ),
    ] {
        let path = write(dir.path(), name, text.as_bytes());
        let csv = commented_csv("#");
        let mut globbed = csv.clone();
        globbed.options.glob = true;
        for (read, got) in [
            ("a read", csv.read_outcome(&path)),
            ("a glob", globbed.read_outcome(&one_file_pattern(&path))),
            ("a scan", csv.scan_outcome(&path)),
        ] {
            assert_eq!(
                got.map(|df| (df.height(), column_text(&df, "a"))),
                Ok((column_a.len(), column_a.clone())),
                "{} of {}",
                read,
                name
            );
        }
    }
}

fn column_text(df: &DataFrame, name: &str) -> Vec<String> {
    let text = df.column(name).unwrap().cast(&DataType::String).unwrap();
    text.str()
        .unwrap()
        .iter()
        .map(|v| v.expect("no nulls").to_string())
        .collect()
}

#[test]
fn a_tail_of_a_file_the_counter_finds_no_rows_in_fails_as_the_full_read_does() {
    let dir = tempfile::tempdir().expect("tempdir");
    let csv = commented_csv("#");
    let rows: String = (0..100_000).map(|i| format!("{},{}\n", i, i)).collect();
    let path = write(
        dir.path(),
        "stray.csv",
        format!("a,b\n1,5\"\n{}", rows).as_bytes(),
    );
    let lf = || csv.scan(&path);
    for (read, got) in [
        ("a whole scan", csv.scan_outcome(&path)),
        ("a tail", lf().tail(5).collect().map_err(|e| e.to_string())),
        (
            "a head",
            lf().slice(0, 5).collect().map_err(|e| e.to_string()),
        ),
    ] {
        assert!(
            got.as_ref().is_err_and(|e| e.starts_with("CSV malformed")),
            "{} fails: {:?}",
            read,
            got.map(|df| df.shape())
        );
    }
}

#[test]
fn a_tail_checks_the_row_structure_of_the_batches_it_counts() {
    let dir = tempfile::tempdir().expect("tempdir");
    let csv = commented_csv("#");
    let rows: String = (0..2_000).map(|i| format!("{},{}\n", i, i)).collect();
    let path = write(
        dir.path(),
        "quoted.csv",
        format!("a,b\n\"1,5\n{}", rows).as_bytes(),
    );
    let lf = || csv.scan(&path).select([col("b")]);
    for (read, got) in [
        ("a whole scan", lf().collect().map_err(|e| e.to_string())),
        ("a tail", lf().tail(2).collect().map_err(|e| e.to_string())),
    ] {
        assert!(
            got.as_ref()
                .is_err_and(|e| e.starts_with("CSV malformed")
                    && !e.contains("1999,1999")),
            "{} of column b fails on the row structure alone: {:?}",
            read,
            got.map(|df| df.shape())
        );
    }
}

fn indexed(mut csv: Csv) -> Csv {
    csv.row_index_name = Some(bytes_of("i"));
    csv.options.row_index_offset = 5;
    csv
}

fn slice_outcome(csv: &Csv, path: &Path, offset: i64, n: usize) -> Outcome {
    csv.scan(path)
        .slice(offset, n as IdxSize)
        .collect()
        .map_err(|e| e.to_string())
}

fn ten_rows_then(from: usize, rest: &str) -> String {
    let rows: String = (from..from + 10)
        .map(|i| format!("{},{}\n", i, i))
        .collect();
    format!("a,b\n{}{}", rows, rest)
}

fn two_file_glob(dir: &Path, name: &str, first: &str) -> PathBuf {
    let sub = dir.join(name);
    std::fs::create_dir(&sub).expect("glob directory");
    write(&sub, "a0.csv", first.as_bytes());
    write(&sub, "a1.csv", ten_rows_then(100, "").as_bytes());
    sub.join("a*.csv")
}

#[test]
fn a_slice_under_ignore_errors_is_the_full_reads_cut() {
    let dir = tempfile::tempdir().expect("tempdir");
    let rows: String = (0..20_000).map(|i| format!("v{}\n", i)).collect();
    let unended = write(
        dir.path(),
        "unended.csv",
        format!("a\n{}x#y", rows).as_bytes(),
    );
    let commented = write(
        dir.path(),
        "commented.csv",
        b"a,b\n1,5\"\n2,6\n# note\n3,7\n",
    );
    let stray = write(dir.path(), "stray.csv", b"a,b\n1,5\"\n2,6\n3,7\n");
    let glob = two_file_glob(
        dir.path(),
        "glob",
        &ten_rows_then(10, "1,5\"\n2,6\n# note\n3,7\n"),
    );
    let mut violations = Vec::new();
    for (prefix, path) in [
        (Some("#"), &unended),
        (Some("#"), &commented),
        (None, &stray),
        (Some("#"), &glob),
        (None, &glob),
    ] {
        let mut plain = Csv {
            comment_prefix: prefix.map(bytes_of),
            ..Default::default()
        };
        plain.options.ignore_errors = true;
        for csv in [plain.clone(), indexed(plain)] {
            let full = csv.scan_collect(path);
            let total = full.height();
            let mut cuts: Vec<(i64, usize)> = (1..=4)
                .flat_map(|n| [(0, n), (-(n as i64), n), (-(n as i64), 1)])
                .collect();
            cuts.extend([(-12, 12), (0, total), (-(total as i64), total)]);
            cuts.sort_unstable();
            cuts.dedup();
            for (offset, n) in cuts {
                let expected = Ok(full.slice(offset, n));
                let got = slice_outcome(&csv, path, offset, n);
                if !same_outcome(&got, &expected) {
                    violations.push(format!(
                        "slice({}, {}) of {:?}, prefix {:?}, row index {}: {:?}",
                        offset,
                        n,
                        path,
                        prefix,
                        csv.row_index_name.is_some(),
                        got.map(|df| df.shape())
                    ));
                }
            }
            for n in [1, 2] {
                let mut head = csv.clone();
                head.options.has_n_rows = true;
                head.options.n_rows = n;
                let got = head.read_outcome(path);
                if !same_outcome(&got, &Ok(full.head(Some(n)))) {
                    violations.push(format!(
                        "n rows {} of {:?}, prefix {:?}: {:?}",
                        n,
                        path,
                        prefix,
                        got.map(|df| df.shape())
                    ));
                }
            }
        }
    }
    assert!(violations.is_empty(), "{}", violations.join("\n"));
}

#[test]
fn a_glob_tail_fails_on_a_malformed_earlier_file_as_the_full_read_does() {
    let dir = tempfile::tempdir().expect("tempdir");
    let csv = indexed(commented_csv("#"));
    let bad = two_file_glob(
        dir.path(),
        "bad",
        &ten_rows_then(10, "1,5\"\n2,6\n# note\n3,7\n"),
    );
    let good = two_file_glob(
        dir.path(),
        "good",
        &ten_rows_then(10, "1,5\n2,6\n# note\n3,7\n"),
    );
    for (read, got) in [
        ("a whole scan", csv.scan_outcome(&bad)),
        ("a tail of 2", slice_outcome(&csv, &bad, -2, 2)),
        ("a tail of 10", slice_outcome(&csv, &bad, -10, 10)),
        ("a tail of 11", slice_outcome(&csv, &bad, -11, 11)),
    ] {
        assert!(
            got.as_ref().is_err_and(|e| e.starts_with("CSV malformed")),
            "{} of the glob fails: {:?}",
            read,
            got.map(|df| df.shape())
        );
    }
    let full = csv.scan_collect(&good);
    assert_eq!(full.height(), 23);
    for n in [1, 2, 10, 11, 13, 14, 23, 30] {
        let got = slice_outcome(&csv, &good, -(n as i64), n);
        assert!(
            same_outcome(&got, &Ok(full.tail(Some(n)))),
            "a tail of {} of the well-formed glob: {:?}",
            n,
            got.map(|df| df.shape())
        );
    }
    let last = slice_outcome(&csv, &good, -2, 2).expect("a tail of 2");
    let index = last.column("i").unwrap().cast(&DataType::Int64).unwrap();
    let index: Vec<i64> = index.i64().unwrap().into_no_null_iter().collect();
    assert_eq!(index, [26, 27]);
}

fn numbered_rows(rows: Range<usize>) -> String {
    let rows: String = rows.map(|i| format!("{},{}\n", i, i)).collect();
    format!("a,b\n{}", rows)
}

#[test]
fn a_short_slice_from_the_end_past_whole_frames_is_the_full_reads_cut() {
    let dir = tempfile::tempdir().expect("tempdir");
    let sub = dir.path().join("small-then-large");
    std::fs::create_dir(&sub).expect("glob directory");
    for (i, rows) in [0..10, 10..20, 20..30, 30..1030].into_iter().enumerate() {
        write(&sub, &format!("f{}.csv", i), numbered_rows(rows).as_bytes());
    }
    let single = write(
        dir.path(),
        "single.csv",
        numbered_rows(0..40_000).as_bytes(),
    );
    let mut ignoring = Csv::default();
    ignoring.options.ignore_errors = true;
    let mut violations = Vec::new();
    for (path, offset, n) in
        [(sub.join("f*.csv"), -500, 5), (single, -11_783, 4_479)]
    {
        for csv in [commented_csv("#"), ignoring.clone()] {
            for csv in [csv.clone(), indexed(csv)] {
                let expected = Ok(csv.scan_collect(&path).slice(offset, n));
                let got = slice_outcome(&csv, &path, offset, n);
                if !same_outcome(&got, &expected) {
                    violations.push(format!(
                        "slice({}, {}) of {:?}, prefix {}, row index {}: {:?}",
                        offset,
                        n,
                        path,
                        csv.comment_prefix.is_some(),
                        csv.row_index_name.is_some(),
                        got.map(|df| df.shape())
                    ));
                }
            }
        }
    }
    assert!(violations.is_empty(), "{}", violations.join("\n"));
}

#[derive(Clone)]
struct LawFixture {
    label: &'static str,
    csv: Csv,
    eol: &'static str,
    header: &'static [&'static str],
    comments: fn(usize, usize) -> Vec<String>,
    row: fn(usize) -> String,
    bytes: usize,
    footer: Vec<String>,
    trailer: &'static str,
}

struct LawText {
    body: String,
    first_batch_rows: usize,
}

fn plain_row(i: usize) -> String {
    format!("{},v{}", i, i % 13)
}

fn comment_run() -> Vec<String> {
    let line = |i| format!("# a run longer than the largest batch {:06}", i);
    let lines = LARGEST_BATCH_BYTES / line(0).len() + 1_000;
    (0..lines).map(line).collect()
}

fn every_ten(prefix: &str, i: usize) -> Vec<String> {
    match i % 10 {
        0 => vec![format!("{} note {}", prefix, i)],
        _ => vec![],
    }
}

fn law_fixture(label: &'static str, set: fn(&mut LawFixture)) -> LawFixture {
    let mut fixture = LawFixture {
        label,
        csv: commented_csv("#"),
        eol: "\n",
        header: &["id,s"],
        comments: |i, _| every_ten("#", i),
        row: plain_row,
        bytes: LAW_FIXTURE_BYTES,
        footer: vec![],
        trailer: "",
    };
    set(&mut fixture);
    fixture
}

impl LawFixture {
    fn text(&self) -> LawText {
        let mut body: String = self
            .header
            .iter()
            .map(|line| format!("{}{}", line, self.eol))
            .collect();
        let mut first_batch_rows = 0;
        let mut i = 0;
        while body.len() < self.bytes {
            for comment in (self.comments)(i, body.len()) {
                body.push_str(&comment);
                body.push_str(self.eol);
            }
            body.push_str(&(self.row)(i));
            body.push_str(self.eol);
            if body.len() <= FIRST_BATCH_BYTES {
                first_batch_rows = i + 1;
            }
            i += 1;
        }
        for line in &self.footer {
            body.push_str(line);
            body.push_str(self.eol);
        }
        LawText {
            body,
            first_batch_rows,
        }
    }
}

fn law_fixtures() -> Vec<LawFixture> {
    vec![
        law_fixture("comments around the header", |f| {
            f.header = &["# first", "# second", "id,s", "# after the header"];
        }),
        law_fixture("runs of comments", |f| {
            f.comments = |i, _| match i % 37 {
                0 => vec!["# run".to_string(); i % 5 + 1],
                _ => vec![],
            };
        }),
        law_fixture("a quote in a comment", |f| {
            f.comments = |i, _| match i % 10 {
                0 => vec![format!("# say \"hi {}", i)],
                _ => vec![],
            };
        }),
        law_fixture("a quoted line that starts with the prefix", |f| {
            f.row = |i| match i % 25 {
                0 => format!("{},\"first\n# not a comment\"", i),
                _ => plain_row(i),
            };
        }),
        law_fixture("crlf", |f| f.eol = "\r\n"),
        law_fixture("batches that grow past a short slice from the end", |f| {
            f.bytes = LONG_LAW_FIXTURE_BYTES;
        }),
        law_fixture("the // prefix", |f| {
            f.csv = commented_csv("//");
            f.comments = |i, _| every_ten("//", i);
        }),
        law_fixture("a final comment without a newline", |f| {
            f.trailer = "# the end";
        }),
        law_fixture("a final row without a newline, # second", |f| {
            f.row = |i| format!("r{},v{}", i, i % 13);
            f.trailer = "x#y";
        }),
        law_fixture("a final row without a newline, // second", |f| {
            f.csv = commented_csv("//");
            f.comments = |i, _| every_ten("//", i);
            f.row = |i| format!("r{},v{}", i, i % 13);
            f.trailer = "x//y";
        }),
        law_fixture("a final quoted field holding a comment line", |f| {
            f.trailer = "-1,\"x\n#y\"";
        }),
        law_fixture("comments across the first batch boundary", |f| {
            f.comments = |i, at| match (FIRST_BATCH_BYTES * 5 / 8
                ..FIRST_BATCH_BYTES * 3 / 2)
                .contains(&at)
            {
                true => vec![format!("# across {}", i); 3],
                false => every_ten("#", i),
            };
        }),
        law_fixture("two rows skipped after the header", |f| {
            f.header = &["id,s", "# a", "# b"];
            f.csv.options.skip_rows_after_header = 2;
        }),
        law_fixture("a comment run longer than a batch, twice", |f| {
            f.comments = |i, _| match i {
                0 => comment_run(),
                _ => every_ten("#", i),
            };
            f.bytes += comment_run().concat().len();
            f.footer = comment_run();
        }),
        law_fixture("a stray quote resynchronised by a quoted comment", |f| {
            f.header = &["a,b"];
            f.comments = |_, _| vec![];
            f.row = |i| match i {
                0..8_000 => format!("r{},v{}", i, i % 7),
                8_000 => {
                    format!("p1,a\"b\np2,\"x\n{}\"\n# \"", "y".repeat(40_000))
                }
                _ => format!("s{},v{}", i, i % 7),
            };
        }),
    ]
}

struct LawFiles {
    clean: PathBuf,
    terminated: PathBuf,
    bad: PathBuf,
}

fn law_glob(dir: &Path, name: &str, texts: [&str; 2]) -> PathBuf {
    let sub = dir.join(name);
    std::fs::create_dir(&sub).expect("glob directory");
    for (i, text) in texts.iter().enumerate() {
        write(&sub, &format!("{}.csv", i), text.as_bytes());
    }
    sub.join("*.csv")
}

impl LawFiles {
    fn write(
        dir: &Path,
        fixture: &LawFixture,
        text: &LawText,
        glob: bool,
    ) -> Self {
        let LawText { body, .. } = text;
        let (eol, trailer) = (fixture.eol, fixture.trailer);
        let terminated = match trailer {
            "" => body.clone(),
            _ => format!("{}{}{}", body, trailer, eol),
        };
        let clean = format!("{}{}", body, trailer);
        let bad = format!("{}{}{}{}", body, BAD_ROW, eol, trailer);
        match glob {
            false => LawFiles {
                clean: write(dir, "clean.csv", clean.as_bytes()),
                terminated: write(dir, "terminated.csv", terminated.as_bytes()),
                bad: write(dir, "bad.csv", bad.as_bytes()),
            },
            true => LawFiles {
                clean: law_glob(dir, "clean", [&terminated, &clean]),
                terminated: law_glob(
                    dir,
                    "terminated",
                    [&terminated, &terminated],
                ),
                bad: law_glob(dir, "bad", [&bad, &terminated]),
            },
        }
    }
}

struct LawRead<'a> {
    label: String,
    csv: Csv,
    files: &'a LawFiles,
    full: DataFrame,
    bad_full: Option<DataFrame>,
    first_batch_rows: usize,
}

fn same_frame(a: &DataFrame, b: &DataFrame) -> bool {
    a.schema() == b.schema() && a.equals_missing(b)
}

impl LawRead<'_> {
    fn lens(&self) -> Vec<usize> {
        let (first, total) = (self.first_batch_rows, self.full.height());
        vec![
            0,
            1,
            2,
            99,
            100,
            first.saturating_sub(1),
            first,
            first + 1,
            total - 1,
            total,
            total + 5,
        ]
    }

    fn offsets(&self) -> Vec<i64> {
        let (first, total) =
            (self.first_batch_rows as i64, self.full.height() as i64);
        vec![
            0,
            1,
            1000,
            first + 1,
            8_001,
            total / 2,
            -1,
            -1000,
            -(first + 1),
            -(total / 4),
            -(total * 3 / 8),
            -(total / 2),
            -total,
        ]
    }

    fn ends_in_the_first_two_batches(&self, offset: i64, n: usize) -> bool {
        offset >= 0 && offset as usize + n <= self.first_batch_rows + 100
    }

    fn bad_slice(&self, offset: i64, n: usize) -> Option<Option<DataFrame>> {
        match &self.bad_full {
            Some(bad_full) => Some(Some(bad_full.slice(offset, n))),
            None if offset < 0 && n > 0 => Some(None),
            None if !self.csv.options.ignore_errors
                && self.ends_in_the_first_two_batches(offset, n) =>
            {
                Some(Some(self.full.slice(offset, n)))
            }
            None => None,
        }
    }

    fn violation(
        &self,
        read: String,
        got: Outcome,
        expected: Option<&DataFrame>,
    ) -> Option<String> {
        let holds = match expected {
            Some(expected) => {
                got.as_ref().is_ok_and(|got| same_frame(got, expected))
            }
            None => got.is_err(),
        };
        match holds {
            true => None,
            false => Some(format!(
                "{}: {} gave {:?}, expected {:?}",
                self.label,
                read,
                got.map(|df| df.shape()),
                expected.map(|df| df.shape())
            )),
        }
    }

    fn scan_slice_violations(&self) -> Vec<String> {
        let mut violations = Vec::new();
        for offset in self.offsets() {
            for n in self.lens() {
                let expected = Some(self.full.slice(offset, n));
                let paths = [
                    (&self.files.terminated, Some(expected.clone())),
                    (&self.files.clean, Some(expected)),
                    (&self.files.bad, self.bad_slice(offset, n)),
                ];
                for (path, expected) in paths {
                    let Some(expected) = expected else {
                        continue;
                    };
                    let got = self
                        .csv
                        .scan(path)
                        .slice(offset, n as IdxSize)
                        .collect()
                        .map_err(|e| e.to_string());
                    let read =
                        format!("slice({}, {}) of {:?}", offset, n, path);
                    violations.extend(self.violation(
                        read,
                        got,
                        expected.as_ref(),
                    ));
                }
            }
        }
        violations
    }

    fn n_rows_violations(&self) -> Vec<String> {
        self.lens()
            .into_iter()
            .filter_map(|n| {
                let mut read = self.csv.clone();
                read.options.has_n_rows = true;
                read.options.n_rows = n;
                let got = read.read_outcome(&self.files.terminated);
                self.violation(
                    format!("n rows {}", n),
                    got,
                    Some(&self.full.head(Some(n))),
                )
            })
            .collect()
    }
}

fn law_violations(
    fixture: &LawFixture,
    dir: &Path,
    glob: bool,
    ignore_errors: bool,
) -> Vec<String> {
    let text = fixture.text();
    let files = LawFiles::write(dir, fixture, &text, glob);
    let mut violations = Vec::new();
    for row_index in [None, Some(bytes_of("i"))] {
        let label = format!(
            "{}, glob {}, ignore errors {}, row index {}",
            fixture.label,
            glob,
            ignore_errors,
            row_index.is_some()
        );
        let mut csv = Csv {
            row_index_name: row_index,
            ..fixture.csv.clone()
        };
        csv.options.ignore_errors = ignore_errors;
        let bad_full = csv.scan_outcome(&files.bad).ok();
        if !ignore_errors && bad_full.is_some() {
            violations.push(format!("{}: the bad row reads", label));
        }
        let full = match csv.scan_outcome(&files.terminated) {
            Ok(full) => full,
            Err(e) => {
                violations
                    .push(format!("{}: the full read failed: {}", label, e));
                continue;
            }
        };
        let read = LawRead {
            label,
            csv,
            files: &files,
            full,
            bad_full,
            first_batch_rows: text.first_batch_rows,
        };
        violations.extend(read.scan_slice_violations());
        violations.extend(read.n_rows_violations());
    }
    violations
}

#[test]
fn a_pushed_slice_with_comments_equals_the_full_read_cut() {
    let fixtures = law_fixtures();
    let runs: Vec<(&LawFixture, bool, bool)> = fixtures
        .iter()
        .flat_map(|fixture| {
            [(false, false), (false, true), (true, false), (true, true)]
                .map(|(glob, ignore_errors)| (fixture, glob, ignore_errors))
        })
        .collect();
    let violations: Vec<String> = std::thread::scope(|scope| {
        let checks: Vec<_> = runs
            .iter()
            .map(|&(fixture, glob, ignore_errors)| {
                scope.spawn(move || {
                    let dir = tempfile::tempdir().expect("tempdir");
                    law_violations(fixture, dir.path(), glob, ignore_errors)
                })
            })
            .collect();
        checks
            .into_iter()
            .flat_map(|check| check.join().expect("a fixture's check"))
            .collect()
    });
    assert!(violations.is_empty(), "{}", violations.join("\n"));
}
