use super::test_util::*;
use super::*;
use std::path::Path;

type Writer = extern "C" fn(*mut DataFrame, *const c_char) -> i32;

const WRITERS: [(&str, Writer); 3] = [
    ("csv", dataframe_write_csv),
    ("parquet", dataframe_write_parquet),
    ("json", dataframe_write_json),
];

fn names(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

fn write_to(writer: Writer, path: &Path) -> i32 {
    let xs = make_i64("x", &[1, 2]);
    let df = make_df(&[xs]);
    let p = cstr(path.to_str().unwrap());
    let rc = writer(df, p.as_ptr());
    dataframe_drop(df);
    series_drop(xs);
    rc
}

fn read_csv(path: &str) -> *mut DataFrame {
    let p = cstr(path);
    dataframe_read_csv_with_options(
        p.as_ptr(),
        CompatCsvOptions::default(),
        ptr::null(),
        ptr::null(),
        0,
        ptr::null(),
        ptr::null(),
        0,
    )
}

fn read_parquet(path: &str) -> *mut DataFrame {
    let p = cstr(path);
    dataframe_read_parquet(p.as_ptr())
}

fn height_of(df: *mut DataFrame) -> usize {
    assert!(!df.is_null(), "{:?}", recorded_error());
    let height = dataframe_height(df);
    dataframe_drop(df);
    height
}

#[test]
fn a_new_file_is_staged_and_renamed() {
    for (ext, writer) in WRITERS {
        let dir = tempfile::tempdir().expect("tempdir");
        assert_eq!(write_to(writer, &dir.path().join(format!("new.{ext}"))), 0);
        assert_eq!(names(dir.path()), vec![format!("new.{ext}")]);
    }
}

#[cfg(unix)]
#[test]
fn a_symlink_target_keeps_the_link() {
    for (ext, writer) in WRITERS {
        let dir = tempfile::tempdir().expect("tempdir");
        let real = dir.path().join(format!("real.{ext}"));
        let link = dir.path().join(format!("link.{ext}"));
        std::fs::write(&real, "OLD").unwrap();
        std::os::unix::fs::symlink(format!("real.{ext}"), &link).unwrap();
        assert_eq!(write_to(writer, &link), 0, "{ext}");
        assert!(std::fs::symlink_metadata(&link)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_ne!(std::fs::read(&real).unwrap(), b"OLD");
        assert_eq!(
            std::fs::read(&link).unwrap(),
            std::fs::read(&real).unwrap()
        );
        let hard = dir.path().join(format!("hard.{ext}"));
        std::fs::hard_link(&real, &hard).unwrap();
        std::fs::write(&real, "SHARED").unwrap();
        assert_eq!(write_to(writer, &real), 0, "{ext}");
        assert_eq!(std::fs::read(&hard).unwrap(), b"SHARED");
        assert_ne!(std::fs::read(&real).unwrap(), b"SHARED");
        std::fs::remove_file(&hard).unwrap();
        let dangling = dir.path().join(format!("dangling.{ext}"));
        std::os::unix::fs::symlink(format!("made.{ext}"), &dangling).unwrap();
        assert_eq!(write_to(writer, &dangling), 0, "{ext}");
        assert!(std::fs::symlink_metadata(&dangling)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_eq!(
            names(dir.path()),
            vec![
                format!("dangling.{ext}"),
                format!("link.{ext}"),
                format!("made.{ext}"),
                format!("real.{ext}"),
            ]
        );
    }
}

#[cfg(unix)]
#[test]
fn a_read_only_target_is_refused() {
    use std::os::unix::fs::PermissionsExt;
    for (ext, writer) in WRITERS {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join(format!("locked.{ext}"));
        std::fs::write(&path, "OLD").unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o444))
            .unwrap();
        if std::fs::OpenOptions::new().write(true).open(&path).is_ok() {
            return;
        }
        assert_eq!(write_to(writer, &path), 3, "{ext}");
        let reason = recorded_error().expect("a reason");
        assert!(
            reason.starts_with("cannot create file: Permission denied"),
            "{reason}"
        );
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "OLD");
        assert_eq!(names(dir.path()), vec![format!("locked.{ext}")]);
    }
}

#[cfg(unix)]
#[test]
fn a_replaced_file_keeps_its_permission_bits() {
    use std::os::unix::fs::PermissionsExt;
    for (ext, writer) in WRITERS {
        let dir = tempfile::tempdir().expect("tempdir");
        for (before, after) in [
            (0o600, 0o600),
            (0o640, 0o640),
            (0o604, 0o604),
            (0o4755, 0o755),
        ] {
            let path = dir.path().join(format!("kept-{before:o}.{ext}"));
            std::fs::write(&path, "OLD").unwrap();
            std::fs::set_permissions(
                &path,
                std::fs::Permissions::from_mode(before),
            )
            .unwrap();
            assert_eq!(write_to(writer, &path), 0, "{ext}");
            let mode = std::fs::metadata(&path).unwrap().permissions().mode();
            assert_eq!(mode & 0o7777, after, "{ext} {before:o}");
            assert_ne!(std::fs::read(&path).unwrap(), b"OLD");
        }
    }
}

#[cfg(unix)]
#[test]
fn a_new_file_gets_default_permissions() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tempfile::tempdir().expect("tempdir");
    let plain = dir.path().join("plain");
    std::fs::File::create(&plain).unwrap();
    let path = dir.path().join("new.json");
    assert_eq!(write_to(dataframe_write_json, &path), 0);
    let mode =
        |path: &Path| std::fs::metadata(path).unwrap().permissions().mode();
    assert_eq!(mode(&path), mode(&plain));
}

#[cfg(unix)]
#[test]
fn a_fifo_is_written_in_place() {
    use std::io::Read;
    use std::os::unix::fs::FileTypeExt;
    let dir = tempfile::tempdir().expect("tempdir");
    let fifo = dir.path().join("pipe.json");
    let made = std::process::Command::new("mkfifo").arg(&fifo).status();
    if !made.is_ok_and(|status| status.success()) {
        return;
    }
    let reader = {
        let fifo = fifo.clone();
        std::thread::spawn(move || {
            let mut text = String::new();
            std::fs::File::open(fifo)
                .unwrap()
                .read_to_string(&mut text)
                .unwrap();
            text
        })
    };
    assert_eq!(write_to(dataframe_write_json, &fifo), 0);
    assert_eq!(reader.join().unwrap(), r#"[{"x":1},{"x":2}]"#);
    assert!(std::fs::symlink_metadata(&fifo)
        .unwrap()
        .file_type()
        .is_fifo());
    assert_eq!(names(dir.path()), vec!["pipe.json"]);
}

#[cfg(unix)]
#[test]
fn dev_null_is_written_in_place() {
    for (ext, writer) in WRITERS {
        assert_eq!(write_to(writer, Path::new("/dev/null")), 0, "{ext}");
    }
}

#[test]
fn a_long_file_name_is_written() {
    for (ext, writer) in WRITERS {
        let dir = tempfile::tempdir().expect("tempdir");
        let name = format!("{}.{ext}", "x".repeat(249 - ext.len()));
        assert_eq!(name.len(), 250);
        assert_eq!(write_to(writer, &dir.path().join(&name)), 0, "{ext}");
        assert_eq!(names(dir.path()), vec![name]);
    }
}

#[test]
fn a_leftover_staging_file_is_not_read() {
    let dir = tempfile::tempdir().expect("tempdir");
    let at = |name: &str| dir.path().join(name).to_str().unwrap().to_string();
    assert_eq!(write_to(dataframe_write_csv, Path::new(&at("a.csv"))), 0);
    assert_eq!(
        write_to(dataframe_write_parquet, Path::new(&at("a.parquet"))),
        0
    );
    std::fs::write(at(".rkt-polars-1-0.partial"), "x\n99\n99\n99\n").unwrap();
    assert_eq!(height_of(read_csv(&at("*.csv"))), 2);
    assert_eq!(height_of(read_parquet(&at("*.parquet"))), 2);
    let parquet_dir = dir.path().join("parts");
    std::fs::create_dir(&parquet_dir).unwrap();
    std::fs::copy(at("a.parquet"), parquet_dir.join("a.parquet")).unwrap();
    std::fs::write(parquet_dir.join(".rkt-polars-1-1.partial"), "PAR1junk")
        .unwrap();
    assert!(read_parquet(parquet_dir.to_str().unwrap()).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(
        reason.starts_with(
            "directory contained paths with different file extensions"
        ),
        "{reason}"
    );
    assert!(reason.contains(".partial"), "{reason}");
}

#[test]
fn a_directory_target_leaves_no_staging_file() {
    for (ext, writer) in WRITERS {
        let dir = tempfile::tempdir().expect("tempdir");
        let sub = dir.path().join("sub");
        std::fs::create_dir(&sub).unwrap();
        assert_ne!(write_to(writer, &sub), 0, "{ext}");
        let reason = recorded_error().expect("a reason");
        assert!(reason.starts_with("cannot create file: "), "{reason}");
        assert_eq!(names(dir.path()), vec!["sub"]);
        assert!(names(&sub).is_empty());
    }
}

#[test]
fn a_failed_write_removes_its_staging_file() {
    let dir = tempfile::tempdir().expect("tempdir");
    let path = dir.path().join("keep.json");
    std::fs::write(&path, "PRECIOUS").unwrap();
    let bytes: [&[u8]; 1] = [b"p"];
    let df = Box::into_raw(Box::new(
        DataFrame::new_infer_height(vec![
            Series::new("b".into(), &bytes).into()
        ])
        .unwrap(),
    ));
    let p = cstr(path.to_str().unwrap());
    assert_eq!(dataframe_write_json(df, p.as_ptr()), 4);
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "PRECIOUS");
    assert_eq!(names(dir.path()), vec!["keep.json"]);
    dataframe_drop(df);
}
