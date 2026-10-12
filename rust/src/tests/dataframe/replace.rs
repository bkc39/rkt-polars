use super::test_util::*;
use super::*;
use std::os::unix::fs::{FileTypeExt, PermissionsExt};
use std::path::Path;

type Writer = extern "C" fn(*mut DataFrame, *const c_char) -> i32;

const WRITERS: [(&str, Writer); 3] = [
    ("csv", dataframe_write_csv),
    ("parquet", dataframe_write_parquet),
    ("ndjson", dataframe_write_json_lines),
];

fn with_frame(values: &[i64], body: impl FnOnce(*mut DataFrame)) {
    let xs = make_i64("x", values);
    let df = make_df(&[xs]);
    body(df);
    dataframe_drop(df);
    series_drop(xs);
}

fn write(df: *mut DataFrame, path: &Path, writer: Writer) -> i32 {
    let p = cstr(path.to_str().unwrap());
    writer(df, p.as_ptr())
}

fn mode(path: &Path) -> u32 {
    std::fs::metadata(path).unwrap().permissions().mode() & 0o7777
}

fn chmod(path: &Path, mode: u32) {
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
        .unwrap();
}

fn entries(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}

fn parquet_height(path: &Path) -> usize {
    let p = cstr(path.to_str().unwrap());
    let df = dataframe_read_parquet(p.as_ptr());
    assert!(!df.is_null(), "{:?}: {:?}", path, recorded_error());
    let height = unsafe { (*df).height() };
    dataframe_drop(df);
    height
}

#[test]
fn a_replaced_file_keeps_its_permission_bits_and_a_new_file_gets_the_default() {
    let dir = tempfile::tempdir().expect("tempdir");
    let default = dir.path().join("default");
    drop(std::fs::File::create(&default).unwrap());
    with_frame(&[1, 2, 3], |df| {
        for (ext, writer) in WRITERS {
            let fresh = dir.path().join(format!("fresh.{}", ext));
            assert_eq!(write(df, &fresh, writer), 0);
            assert_eq!(mode(&fresh), mode(&default), "{}", ext);
            for kept in [0o600, 0o640, 0o604] {
                let path = dir.path().join(format!("kept-{:o}.{}", kept, ext));
                assert_eq!(write(df, &path, writer), 0);
                chmod(&path, kept);
                assert_eq!(write(df, &path, writer), 0);
                assert_eq!(mode(&path), kept, "{}", ext);
            }
        }
    });
}

#[test]
fn a_target_the_caller_cannot_write_is_refused_and_kept() {
    let dir = tempfile::tempdir().expect("tempdir");
    with_frame(&[1, 2, 3], |df| {
        for (ext, writer) in WRITERS {
            let path = dir.path().join(format!("locked.{}", ext));
            assert_eq!(write(df, &path, writer), 0);
            let before = std::fs::read(&path).unwrap();
            chmod(&path, 0o444);
            let names = entries(dir.path());
            if std::fs::OpenOptions::new().write(true).open(&path).is_ok() {
                assert_eq!(write(df, &path, writer), 0);
                continue;
            }
            assert_eq!(write(df, &path, writer), 3, "{}", ext);
            assert_eq!(
                recorded_error().as_deref(),
                Some("cannot create file: Permission denied (os error 13)")
            );
            assert_eq!(std::fs::read(&path).unwrap(), before);
            assert_eq!(mode(&path), 0o444);
            assert_eq!(entries(dir.path()), names);
        }
    });
}

#[test]
fn a_symlink_survives_and_its_pointee_is_replaced() {
    let dir = tempfile::tempdir().expect("tempdir");
    let real = dir.path().join("real.csv");
    let soft = dir.path().join("soft.csv");
    let hard = dir.path().join("hard.csv");
    with_frame(&[1, 2, 3], |df| {
        assert_eq!(write(df, &real, dataframe_write_csv), 0);
    });
    std::os::unix::fs::symlink(&real, &soft).unwrap();
    std::fs::hard_link(&real, &hard).unwrap();
    let before = std::fs::read(&real).unwrap();
    with_frame(&[7, 8, 9, 10], |df| {
        assert_eq!(write(df, &soft, dataframe_write_csv), 0);
    });
    let soft_meta = std::fs::symlink_metadata(&soft).unwrap();
    assert!(soft_meta.file_type().is_symlink());
    let after = std::fs::read(&real).unwrap();
    assert_ne!(after, before);
    assert_eq!(std::fs::read(&soft).unwrap(), after);
    assert_eq!(std::fs::read(&hard).unwrap(), before);
    assert_eq!(
        entries(dir.path()),
        vec!["hard.csv", "real.csv", "soft.csv"]
    );

    let dangling = dir.path().join("dangling.csv");
    let pointee = dir.path().join("pointee.csv");
    std::os::unix::fs::symlink(&pointee, &dangling).unwrap();
    with_frame(&[1], |df| {
        assert_eq!(write(df, &dangling, dataframe_write_csv), 0);
    });
    assert!(std::fs::symlink_metadata(&dangling)
        .unwrap()
        .file_type()
        .is_symlink());
    assert_eq!(std::fs::read_to_string(&pointee).unwrap(), "x\n1\n");
}

#[test]
fn a_fifo_is_written_in_place() {
    let dir = tempfile::tempdir().expect("tempdir");
    let fifo = dir.path().join("pipe.csv");
    let made = std::process::Command::new("mkfifo").arg(&fifo).status();
    if !made.is_ok_and(|status| status.success()) {
        eprintln!("skipped: no mkfifo");
        return;
    }
    let reader = {
        let fifo = fifo.clone();
        std::thread::spawn(move || std::fs::read_to_string(fifo).unwrap())
    };
    with_frame(&[1, 2], |df| {
        assert_eq!(write(df, &fifo, dataframe_write_csv), 0);
    });
    assert_eq!(reader.join().unwrap(), "x\n1\n2\n");
    let meta = std::fs::symlink_metadata(&fifo).unwrap();
    assert!(meta.file_type().is_fifo());
    assert_eq!(entries(dir.path()), vec!["pipe.csv"]);
}

#[test]
fn dev_null_takes_every_writer() {
    with_frame(&[1, 2, 3], |df| {
        for (ext, writer) in WRITERS {
            assert_eq!(write(df, Path::new("/dev/null"), writer), 0, "{}", ext);
        }
    });
    let meta = std::fs::symlink_metadata("/dev/null").unwrap();
    assert!(meta.file_type().is_char_device());
}

#[test]
fn a_250_byte_name_is_written() {
    let dir = tempfile::tempdir().expect("tempdir");
    with_frame(&[1, 2, 3], |df| {
        for (ext, writer) in WRITERS {
            let name = format!("{}.{}", "n".repeat(249 - ext.len()), ext);
            assert_eq!(name.len(), 250);
            let path = dir.path().join(&name);
            assert_eq!(write(df, &path, writer), 0, "{:?}", recorded_error());
            assert_eq!(write(df, &path, writer), 0, "{:?}", recorded_error());
            assert!(entries(dir.path()).contains(&name));
        }
        assert_eq!(entries(dir.path()).len(), 3);
    });
}

#[test]
fn a_leftover_staging_file_is_not_read_back() {
    let dir = tempfile::tempdir().expect("tempdir");
    let data = dir.path().join("data");
    std::fs::create_dir(&data).unwrap();
    let real = data.join("a.parquet");
    with_frame(&[1, 2, 3], |df| {
        assert_eq!(write(df, &real, dataframe_write_parquet), 0);
    });
    std::fs::copy(&real, data.join(".rkt-polars-1-0.partial")).unwrap();
    assert_eq!(parquet_height(&data), 3);
    assert_eq!(parquet_height(&data.join("*.parquet")), 3);
    assert_eq!(parquet_height(&data.join("*")), 3);
}

#[test]
fn a_directory_target_leaves_nothing_in_its_parent() {
    let dir = tempfile::tempdir().expect("tempdir");
    let sub = dir.path().join("sub");
    std::fs::create_dir(&sub).unwrap();
    with_frame(&[1, 2, 3], |df| {
        for (ext, writer) in WRITERS {
            assert_eq!(write(df, &sub, writer), 3, "{}", ext);
            assert_eq!(
                recorded_error().as_deref(),
                Some("cannot create file: Is a directory (os error 21)")
            );
            assert_eq!(entries(dir.path()), vec!["sub"]);
            assert!(entries(&sub).is_empty());
        }
    });
}
