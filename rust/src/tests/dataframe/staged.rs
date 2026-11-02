use super::io::{write_csv, write_parquet};
use super::test_util::*;
use super::*;
use std::path::Path;

type Writer = extern "C" fn(*mut DataFrame, *const c_char) -> i32;

extern "C" fn write_ndjson(df: *mut DataFrame, path: *const c_char) -> i32 {
    dataframe_write_ndjson_with_options(df, path, 0, false, 0, true)
}

const WRITERS: [(&str, Writer); 4] = [
    ("csv", write_csv),
    ("parquet", write_parquet),
    ("json", dataframe_write_json),
    ("ndjson", write_ndjson),
];

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
    super::io::read_csv(p.as_ptr())
}

fn read_parquet(path: &str) -> *mut DataFrame {
    let p = cstr(path);
    super::io::read_parquet(p.as_ptr())
}

fn read_ndjson(path: &str) -> *mut DataFrame {
    let p = cstr(path);
    dataframe_read_ndjson_with_options_v2(
        p.as_ptr(),
        CompatNdjsonOptions::default(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
        ptr::null(),
    )
}

fn height_of(df: *mut DataFrame) -> usize {
    let reason = recorded_error();
    assert!(!df.is_null(), "{reason:?}");
    let height = dataframe_height(df);
    dataframe_drop(df);
    height
}

#[test]
fn a_new_file_is_staged_and_renamed() {
    for (ext, writer) in WRITERS {
        let dir = scratch_dir();
        assert_eq!(write_to(writer, &dir.path().join(format!("new.{ext}"))), 0);
        assert_eq!(entries(dir.path()), vec![format!("new.{ext}")]);
    }
}

#[cfg(unix)]
#[test]
fn a_symlink_target_keeps_the_link() {
    for (ext, writer) in WRITERS {
        let dir = scratch_dir();
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
            entries(dir.path()),
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
        let dir = scratch_dir();
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
        assert_eq!(entries(dir.path()), vec![format!("locked.{ext}")]);
    }
}

#[cfg(unix)]
#[test]
fn a_replaced_file_keeps_its_permission_bits() {
    use std::os::unix::fs::PermissionsExt;
    for (ext, writer) in WRITERS {
        let dir = scratch_dir();
        for kept in [0o600, 0o640, 0o604] {
            let path = dir.path().join(format!("kept-{kept:o}.{ext}"));
            std::fs::write(&path, "OLD").unwrap();
            std::fs::set_permissions(
                &path,
                std::fs::Permissions::from_mode(kept),
            )
            .unwrap();
            assert_eq!(write_to(writer, &path), 0, "{ext}");
            let mode = std::fs::metadata(&path).unwrap().permissions().mode();
            assert_eq!(mode & 0o7777, kept, "{ext} {kept:o}");
            assert_ne!(std::fs::read(&path).unwrap(), b"OLD");
        }
    }
}

#[cfg(unix)]
#[test]
fn a_replaced_file_drops_its_set_id_and_sticky_bits() {
    for (before, after) in [
        (0o100644, 0o644),
        (0o4755, 0o755),
        (0o2750, 0o750),
        (0o1777, 0o777),
        (0o107604, 0o604),
    ] {
        assert_eq!(kept_mode(before), after, "{before:o}");
    }
}

#[cfg(unix)]
#[test]
fn a_new_file_gets_default_permissions() {
    use std::os::unix::fs::PermissionsExt;
    let dir = scratch_dir();
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
    use std::os::unix::fs::FileTypeExt;
    let cases: [(&str, Writer, Option<&str>); 4] = [
        ("csv", write_csv, Some("x\n1\n2\n")),
        ("parquet", write_parquet, None),
        ("json", dataframe_write_json, Some(r#"[{"x":1},{"x":2}]"#)),
        ("ndjson", write_ndjson, Some("{\"x\":1}\n{\"x\":2}\n")),
    ];
    for (ext, writer, expected) in cases {
        let dir = scratch_dir();
        let fifo = dir.path().join(format!("pipe.{ext}"));
        let made = std::process::Command::new("mkfifo").arg(&fifo).status();
        if !made.is_ok_and(|status| status.success()) {
            return;
        }
        let reader = {
            let fifo = fifo.clone();
            std::thread::spawn(move || std::fs::read(fifo).unwrap())
        };
        assert_eq!(write_to(writer, &fifo), 0, "{ext}");
        let bytes = reader.join().unwrap();
        match expected {
            Some(text) => assert_eq!(bytes, text.as_bytes()),
            None => assert!(
                bytes.starts_with(b"PAR1") && bytes.ends_with(b"PAR1"),
                "{ext}"
            ),
        }
        assert!(std::fs::symlink_metadata(&fifo)
            .unwrap()
            .file_type()
            .is_fifo());
        assert_eq!(entries(dir.path()), vec![format!("pipe.{ext}")]);
    }
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
        let dir = scratch_dir();
        let stem = "x".repeat(249 - ext.len());
        let name = format!("{stem}.{ext}");
        assert_eq!(name.len(), 250);
        assert_eq!(write_to(writer, &dir.path().join(&name)), 0, "{ext}");
        assert_eq!(entries(dir.path()), vec![name]);
    }
}

#[test]
fn a_leftover_staging_file_is_not_read() {
    let dir = scratch_dir();
    let at = |name: &str| dir.path().join(name).to_str().unwrap().to_string();
    assert_eq!(write_to(write_csv, Path::new(&at("a.csv"))), 0);
    assert_eq!(write_to(write_parquet, Path::new(&at("a.parquet"))), 0);
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
    let ndjson_dir = dir.path().join("lines");
    std::fs::create_dir(&ndjson_dir).unwrap();
    assert_eq!(write_to(write_ndjson, &ndjson_dir.join("a.ndjson")), 0);
    std::fs::write(ndjson_dir.join(".rkt-polars-1-2.partial"), "{\"x\":99}\n")
        .unwrap();
    let lines =
        |name: &str| ndjson_dir.join(name).to_str().unwrap().to_string();
    assert_eq!(height_of(read_ndjson(&lines("*.ndjson"))), 2);
    assert!(read_ndjson(&lines("")).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains(".partial"), "{reason}");
}

#[test]
fn a_directory_target_leaves_no_staging_file() {
    for (ext, writer) in WRITERS {
        let dir = scratch_dir();
        let sub = dir.path().join("sub");
        std::fs::create_dir(&sub).unwrap();
        assert_eq!(write_to(writer, &sub), 3, "{ext}");
        assert_eq!(
            recorded_error().as_deref(),
            Some("cannot create file: it is a directory")
        );
        assert_eq!(entries(dir.path()), vec!["sub"]);
        assert!(entries(&sub).is_empty());
    }
}

fn binary_frame() -> *mut DataFrame {
    let bytes: [&[u8]; 1] = [b"p"];
    Box::into_raw(Box::new(
        DataFrame::new_infer_height(vec![
            Series::new("b".into(), &bytes).into()
        ])
        .unwrap(),
    ))
}

#[test]
fn a_failed_write_removes_its_staging_file() {
    let dir = scratch_dir();
    let path = dir.path().join("keep.json");
    std::fs::write(&path, "PRECIOUS").unwrap();
    let staged = create_staged(path.to_str().unwrap()).expect("staged");
    assert_eq!(entries(dir.path()).len(), 2);
    assert_eq!(staged.finish(None), 4);
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "PRECIOUS");
    assert_eq!(entries(dir.path()), vec!["keep.json"]);
}

#[test]
fn a_failed_csv_write_keeps_the_existing_file() {
    let dir = scratch_dir();
    let path = dir.path().join("keep.csv");
    std::fs::write(&path, "PRECIOUS").unwrap();
    let rows = [
        Series::new("".into(), &[1i64]),
        Series::new("".into(), &[2i64]),
    ];
    let df = Box::into_raw(Box::new(
        DataFrame::new_infer_height(
            vec![Series::new("l".into(), &rows).into()],
        )
        .unwrap(),
    ));
    let p = cstr(path.to_str().unwrap());
    assert_eq!(write_csv(df, p.as_ptr()), 4);
    assert_eq!(
        recorded_error().as_deref(),
        Some("CSV format does not support nested data")
    );
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "PRECIOUS");
    assert_eq!(entries(dir.path()), vec!["keep.csv"]);
    dataframe_drop(df);
}

#[test]
fn a_failed_rename_removes_its_staging_file() {
    let dir = scratch_dir();
    let target = dir.path().join("out.json");
    let staged = create_staged(target.to_str().unwrap()).expect("staged");
    std::fs::create_dir(&target).unwrap();
    std::fs::write(target.join("inside"), "x").unwrap();
    clear_last_error();
    assert_eq!(staged.finish(Some(())), 4);
    let reason = recorded_error().expect("a reason");
    assert!(reason.starts_with("cannot create file: "), "{reason}");
    assert_eq!(entries(dir.path()), vec!["out.json"]);
    assert_eq!(entries(&target), vec!["inside"]);
}

#[test]
fn a_refused_frame_opens_nothing() {
    let writers: [(&str, Writer); 2] =
        [("json", dataframe_write_json), ("ndjson", write_ndjson)];
    let df = binary_frame();
    for (ext, writer) in writers {
        let dir = scratch_dir();
        let keep = format!("keep.{ext}");
        let path = dir.path().join(&keep);
        std::fs::write(&path, "PRECIOUS").unwrap();
        let p = cstr(path.to_str().unwrap());
        assert_eq!(writer(df, p.as_ptr()), 4, "{ext}");
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "PRECIOUS");
        assert_eq!(entries(dir.path()), vec![keep.clone()]);
        #[cfg(unix)]
        {
            let link = format!("link.{ext}");
            let at = dir.path().join(&link);
            std::os::unix::fs::symlink(format!("made.{ext}"), &at).unwrap();
            let l = cstr(at.to_str().unwrap());
            assert_eq!(writer(df, l.as_ptr()), 4, "{ext}");
            assert_eq!(entries(dir.path()), vec![keep, link]);
        }
    }
    dataframe_drop(df);
}
