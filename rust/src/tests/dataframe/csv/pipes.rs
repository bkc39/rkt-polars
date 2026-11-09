use super::*;
use std::os::unix::fs::OpenOptionsExt;

const PIPED: &[u8] = b"a,b\n1,2\n# c\n3,4\n";

fn read_through_a_fifo(csv: &Csv, path: &Path) -> Option<Outcome> {
    let name = cstr(path.to_str().unwrap());
    if unsafe { libc::mkfifo(name.as_ptr(), 0o600) } != 0 {
        eprintln!(
            "skipped: mkfifo failed: {}",
            std::io::Error::last_os_error()
        );
        return None;
    }
    let writer = {
        let path = path.to_path_buf();
        std::thread::spawn(move || std::fs::write(path, PIPED))
    };
    let got = csv.read_outcome(path);
    let unblock = std::fs::OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_NONBLOCK)
        .open(path);
    let _ = writer.join();
    drop(unblock);
    Some(got)
}

#[test]
fn a_named_pipe_reads_eagerly_whatever_the_keywords() {
    let dir = tempfile::tempdir().expect("tempdir");
    let file = write(dir.path(), "file.csv", PIPED);
    let mut n_rows = commented_csv("#");
    n_rows.options.has_n_rows = true;
    n_rows.options.n_rows = 1;
    let mut plain_n_rows = Csv::default();
    plain_n_rows.options.has_n_rows = true;
    plain_n_rows.options.n_rows = 2;
    for (i, (label, csv, height)) in [
        ("no keywords", Csv::default(), 3),
        ("a comment prefix", commented_csv("#"), 2),
        ("n-rows", plain_n_rows, 2),
        ("a comment prefix and n-rows", n_rows, 1),
    ]
    .into_iter()
    .enumerate()
    {
        let Some(got) =
            read_through_a_fifo(&csv, &dir.path().join(format!("p{}.csv", i)))
        else {
            return;
        };
        let expected = csv.read(&file);
        assert_eq!(expected.height(), height, "{}: the file", label);
        assert!(
            same_outcome(&got, &Ok(expected)),
            "{}: the pipe reads as the file does: {:?}",
            label,
            got.map(|df| df.shape())
        );
    }
}
