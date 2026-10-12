use std::fs::{File, OpenOptions};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::prelude::*;
use crate::*;
use polars::prelude::SerWriter;

pub(crate) const IO_OK: i32 = 0;
pub(crate) const IO_NULL_ARG: i32 = 1;
pub(crate) const IO_BAD_PATH: i32 = 2;
const IO_OPEN_FAILED: i32 = 3;
pub(crate) const IO_WRITE_FAILED: i32 = 4;

fn cannot_create(err: std::io::Error) -> String {
    format!("cannot create file: {}", err)
}

static STAGING_FILES: AtomicUsize = AtomicUsize::new(0);

fn staging_path(dir: &Path) -> PathBuf {
    dir.join(format!(
        ".rkt-polars-{}-{}.partial",
        std::process::id(),
        STAGING_FILES.fetch_add(1, Ordering::Relaxed)
    ))
}

fn resolve_links(path: &Path) -> std::io::Result<PathBuf> {
    let mut target = path.to_path_buf();
    for _ in 0..40 {
        let is_link = std::fs::symlink_metadata(&target)
            .is_ok_and(|meta| meta.file_type().is_symlink());
        if !is_link {
            return Ok(target);
        }
        let link = std::fs::read_link(&target)?;
        target = target.parent().unwrap_or(Path::new("")).join(link);
    }
    Err(std::io::Error::other("too many levels of symbolic links"))
}

/// Where a writer's bytes go: a staging file that `finish` renames onto
/// `target`, or `target` itself when it is not a regular file.
struct Staged {
    file: File,
    staging: Option<PathBuf>,
    target: PathBuf,
}

fn stage(
    target: PathBuf,
    permissions: Option<std::fs::Permissions>,
) -> Result<Staged, String> {
    let dir = match target.parent() {
        Some(dir) if !dir.as_os_str().is_empty() => dir.to_path_buf(),
        _ => PathBuf::from("."),
    };
    let (staging, file) = loop {
        let staging = staging_path(&dir);
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staging)
        {
            Ok(file) => break (staging, file),
            Err(err) if err.kind() == ErrorKind::AlreadyExists => continue,
            Err(err) => return Err(cannot_create(err)),
        }
    };
    let staged = Staged {
        file,
        staging: Some(staging),
        target,
    };
    match permissions
        .map(|permissions| staged.file.set_permissions(permissions))
    {
        Some(Err(err)) => {
            staged.finish(None);
            Err(cannot_create(err))
        }
        _ => Ok(staged),
    }
}

fn create_staged(path: &str) -> Result<Staged, String> {
    let target = resolve_links(Path::new(path)).map_err(cannot_create)?;
    match std::fs::metadata(&target) {
        Err(err) if err.kind() == ErrorKind::NotFound => stage(target, None),
        Err(err) => Err(cannot_create(err)),
        Ok(meta) if meta.is_file() => {
            OpenOptions::new()
                .write(true)
                .open(&target)
                .map_err(cannot_create)?;
            stage(target, Some(meta.permissions()))
        }
        Ok(_) => File::create(&target)
            .map(|file| Staged {
                file,
                staging: None,
                target,
            })
            .map_err(cannot_create),
    }
}

impl Staged {
    fn finish(self, written: Option<()>) -> i32 {
        let Staged {
            file,
            staging,
            target,
        } = self;
        drop(file);
        let Some(staging) = staging else {
            return written.map_or(IO_WRITE_FAILED, |()| IO_OK);
        };
        let renamed = written.and_then(|()| {
            record(std::fs::rename(&staging, &target).map_err(cannot_create))
        });
        match renamed {
            Some(()) => IO_OK,
            None => {
                let _ = std::fs::remove_file(&staging);
                IO_WRITE_FAILED
            }
        }
    }
}

pub(crate) struct PathRules {
    pub glob: bool,
    pub directory: bool,
}

pub(crate) fn is_pattern(path: &str, glob: bool) -> bool {
    glob && path.contains(['*', '?', '['])
}

fn require_path(path: &str, rules: &PathRules) -> PolarsResult<()> {
    if is_pattern(path, rules.glob) {
        return Ok(());
    }
    let metadata = std::fs::metadata(path).map_err(
        |err| polars_err!(ComputeError: "cannot open file: {}", err),
    )?;
    polars_ensure!(
        rules.directory || !metadata.is_dir(),
        ComputeError: "cannot open file: it is a directory; pass a glob pattern such as dir/*.csv"
    );
    Ok(())
}

pub(crate) fn read_path(
    path: *const c_char,
    rules: PathRules,
    read: impl FnOnce(&str) -> PolarsResult<DataFrame>,
) -> *mut DataFrame {
    clear_last_error();
    decode_path(path)
        .and_then(|path| {
            guard_panic(|| {
                record(require_path(path, &rules).and_then(|()| read(path)))
            })
        })
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
}

pub(crate) fn collect_frame(
    path: *const c_char,
    rules: PathRules,
    build: impl FnOnce(&str) -> PolarsResult<LazyFrame>,
) -> *mut DataFrame {
    read_path(path, rules, |path| build(path).and_then(LazyFrame::collect))
}

pub(crate) fn write_frame(
    df_ptr: *mut DataFrame,
    path: *const c_char,
    write: impl FnOnce(&mut File, &mut DataFrame) -> PolarsResult<()>,
) -> i32 {
    clear_last_error();
    if df_ptr.is_null() {
        set_last_error("dataframe is null");
        return IO_NULL_ARG;
    }
    if path.is_null() {
        set_last_error("path is null");
        return IO_NULL_ARG;
    }
    let Some(path_str) = decode_path(path) else {
        return IO_BAD_PATH;
    };
    let Some(mut staged) = record(create_staged(path_str)) else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    let written = guard_panic(|| record(write(&mut staged.file, df)));
    staged.finish(written)
}

#[no_mangle]
pub extern "C" fn dataframe_write_csv(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    write_frame(df_ptr, path, |file, df| {
        CsvWriter::new(file)
            .include_header(true)
            .with_separator(b',')
            .finish(df)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_write_parquet(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    write_frame(df_ptr, path, |file, df| {
        ParquetWriter::new(file).finish(df).map(|_| ())
    })
}

#[no_mangle]
pub extern "C" fn dataframe_read_parquet(
    path: *const c_char,
) -> *mut DataFrame {
    collect_frame(
        path,
        PathRules {
            glob: true,
            directory: true,
        },
        |path| parquet_scan(path, None),
    )
}

#[no_mangle]
pub extern "C" fn dataframe_to_string(df_ptr: *mut DataFrame) -> *const c_char {
    if df_ptr.is_null() {
        return ptr::null();
    }
    let df = unsafe { &*df_ptr };
    rust_string_to_ptr(format!("{}", df))
}

#[no_mangle]
pub extern "C" fn dataframe_shape(df_ptr: *mut DataFrame) -> Shape {
    if df_ptr.is_null() {
        Shape { rows: 0, cols: 0 }
    } else {
        let df = unsafe { &*df_ptr };
        let shape = df.shape();
        Shape {
            rows: shape.0,
            cols: shape.1,
        }
    }
}
