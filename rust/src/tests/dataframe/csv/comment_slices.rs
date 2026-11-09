use super::*;
use std::ops::Range;

const LATE_NA_ROWS: usize = 110_000;
const LATE_NA_BYTES: Range<usize> = 900 * 1024..1200 * 1024;
const FIRST_BATCH_BYTES: usize = 64 * 1024;
const LAW_FIXTURE_BYTES: usize = 200 * 1024;
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
    let rows: String = (0..20_000).map(|i| format!("v{}\n", i)).collect();
    for (prefix, rows, last) in [
        ("#", rows.as_str(), "# the end"),
        ("#", rows.as_str(), "#"),
        ("#", rows.as_str(), "x#y"),
        ("//", rows.as_str(), "x//y"),
        ("//", rows.as_str(), "// the end"),
        ("#", "", "x#y"),
        ("//", "", "x//y"),
    ] {
        let csv = commented_csv(prefix);
        let ended = write(
            dir.path(),
            "ended.csv",
            format!("a\n{}{}\n", rows, last).as_bytes(),
        );
        let reference = csv.scan_collect(&ended);
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
    for (name, text, rows) in [
        ("f8000.csv", format!("a,b\n{}", stray), 28_002),
        ("small.csv", "a,b\n1,x\n# it\"s\n2,y\n3,z\n".to_string(), 3),
        ("quoted.csv", format!("a,b\n{}", quoted), 100_000),
    ] {
        let path = write(dir.path(), name, text.as_bytes());
        let csv = commented_csv("#");
        let mut globbed = csv.clone();
        globbed.options.glob = true;
        let scan = csv.scan_outcome(&path);
        assert_eq!(
            scan.as_ref().map(|df| df.height()),
            Ok(rows),
            "the scan of {}",
            name
        );
        for (read, got) in [
            ("a read", csv.read_outcome(&path)),
            ("a glob", globbed.read_outcome(&one_file_pattern(&path))),
        ] {
            assert!(
                same_outcome(&got, &scan),
                "{} of {}: {:?}",
                read,
                name,
                got.map(|df| df.shape())
            );
        }
    }
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

impl LawFiles {
    fn write(dir: &Path, fixture: &LawFixture, text: &LawText) -> Self {
        let LawText { body, .. } = text;
        let (eol, trailer) = (fixture.eol, fixture.trailer);
        let terminated = match trailer {
            "" => body.clone(),
            _ => format!("{}{}{}", body, trailer, eol),
        };
        LawFiles {
            clean: write(
                dir,
                "clean.csv",
                format!("{}{}", body, trailer).as_bytes(),
            ),
            terminated: write(dir, "terminated.csv", terminated.as_bytes()),
            bad: write(
                dir,
                "bad.csv",
                format!("{}{}{}{}", body, BAD_ROW, eol, trailer).as_bytes(),
            ),
        }
    }
}

struct LawRead<'a> {
    label: String,
    csv: Csv,
    files: &'a LawFiles,
    full: DataFrame,
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
            -(total / 2),
            -total,
        ]
    }

    fn ends_in_the_first_two_batches(&self, offset: i64, n: usize) -> bool {
        offset >= 0 && offset as usize + n <= self.first_batch_rows + 100
    }

    fn violation(
        &self,
        read: String,
        got: Outcome,
        expected: &DataFrame,
    ) -> Option<String> {
        match got.as_ref().is_ok_and(|got| same_frame(got, expected)) {
            true => None,
            false => Some(format!(
                "{}: {} gave {:?}",
                self.label,
                read,
                got.map(|df| df.shape())
            )),
        }
    }

    fn scan_slice_violations(&self) -> Vec<String> {
        let mut violations = Vec::new();
        for offset in self.offsets() {
            for n in self.lens() {
                let expected = self.full.slice(offset, n);
                let near = self.ends_in_the_first_two_batches(offset, n);
                let paths = [
                    (&self.files.terminated, true),
                    (&self.files.clean, true),
                    (&self.files.bad, near),
                ];
                for (path, applies) in paths {
                    if !applies {
                        continue;
                    }
                    let got = self
                        .csv
                        .scan(path)
                        .slice(offset, n as IdxSize)
                        .collect()
                        .map_err(|e| e.to_string());
                    let read = format!(
                        "slice({}, {}) of {:?}",
                        offset,
                        n,
                        path.file_name().unwrap()
                    );
                    violations.extend(self.violation(read, got, &expected));
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
                    &self.full.head(Some(n)),
                )
            })
            .collect()
    }
}

fn law_violations(fixture: &LawFixture, dir: &Path) -> Vec<String> {
    let text = fixture.text();
    let files = LawFiles::write(dir, fixture, &text);
    let mut violations = Vec::new();
    for row_index in [None, Some(bytes_of("i"))] {
        let label =
            format!("{}, row index {}", fixture.label, row_index.is_some());
        let csv = Csv {
            row_index_name: row_index,
            ..fixture.csv.clone()
        };
        if csv.scan_outcome(&files.bad).is_ok() {
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
    let violations: Vec<String> = std::thread::scope(|scope| {
        let checks: Vec<_> = fixtures
            .iter()
            .map(|fixture| {
                scope.spawn(move || {
                    let dir = tempfile::tempdir().expect("tempdir");
                    law_violations(fixture, dir.path())
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
