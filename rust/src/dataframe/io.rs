use std::fs::{File, OpenOptions};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::prelude::*;
use crate::*;
use polars::prelude::{SerReader, SerWriter};

const IO_OK: i32 = 0;
const IO_NULL_ARG: i32 = 1;
const IO_BAD_PATH: i32 = 2;
const IO_OPEN_FAILED: i32 = 3;
const IO_WRITE_FAILED: i32 = 4;

fn open_file(path: &str) -> Option<File> {
    record(File::open(path).map_err(|err| format!("cannot open file: {}", err)))
}

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

#[cfg(unix)]
pub(crate) fn kept_mode(mode: u32) -> u32 {
    mode & 0o777
}

#[cfg(unix)]
fn permission_bits(existing: &std::fs::Metadata) -> std::fs::Permissions {
    use std::os::unix::fs::PermissionsExt;
    std::fs::Permissions::from_mode(kept_mode(existing.permissions().mode()))
}

#[cfg(not(unix))]
fn permission_bits(existing: &std::fs::Metadata) -> std::fs::Permissions {
    existing.permissions()
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

fn in_place(target: PathBuf) -> Result<Staged, String> {
    File::create(&target)
        .map(|file| Staged {
            file,
            staging: None,
            target,
        })
        .map_err(cannot_create)
}

fn stage_existing(target: PathBuf) -> Result<Staged, String> {
    match std::fs::metadata(&target) {
        Err(err) if err.kind() == ErrorKind::NotFound => stage(target, None),
        Err(err) => Err(cannot_create(err)),
        Ok(meta) if meta.is_file() => {
            OpenOptions::new()
                .write(true)
                .open(&target)
                .map_err(cannot_create)?;
            stage(target, Some(permission_bits(&meta)))
        }
        Ok(_) => in_place(target),
    }
}

fn create_staged(path: &str) -> Result<Staged, String> {
    let given = PathBuf::from(path);
    match std::fs::symlink_metadata(&given) {
        Ok(meta) if meta.file_type().is_symlink() => {
            std::fs::canonicalize(&given)
                .map_or_else(|_| in_place(given), stage_existing)
        }
        _ => stage_existing(given),
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

fn read_frame(
    path: *const c_char,
    read: impl FnOnce(File) -> PolarsResult<DataFrame>,
) -> *mut DataFrame {
    clear_last_error();
    decode_path(path)
        .and_then(open_file)
        .and_then(|file| guard_panic(|| record(read(file))))
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
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
pub extern "C" fn dataframe_write_json_lines(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    write_frame(df_ptr, path, |file, df| {
        JsonWriter::new(file)
            .with_json_format(JsonFormat::JsonLines)
            .finish(df)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_read_json_lines(
    path: *const c_char,
) -> *mut DataFrame {
    read_frame(path, |file| {
        JsonReader::new(file)
            .with_json_format(JsonFormat::JsonLines)
            .finish()
    })
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
