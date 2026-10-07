use crate::prelude::*;
use crate::*;
use polars::prelude::{SerReader, SerWriter};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

const IO_OK: i32 = 0;
const IO_NULL_ARG: i32 = 1;
const IO_BAD_PATH: i32 = 2;
const IO_OPEN_FAILED: i32 = 3;
const IO_WRITE_FAILED: i32 = 4;

fn open_file(path: &str) -> Option<std::fs::File> {
    record(
        std::fs::File::open(path)
            .map_err(|err| format!("cannot open file: {}", err)),
    )
}

fn staging_path(target: &Path) -> PathBuf {
    static NEXT: AtomicUsize = AtomicUsize::new(0);
    let name = target
        .file_name()
        .map_or_else(|| "frame".into(), |name| name.to_string_lossy());
    let dir = target
        .parent()
        .filter(|dir| !dir.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    dir.join(format!(
        ".{}.{}-{}.tmp",
        name,
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}

/// A writer writes a staging file beside `path` and renames it over `path`
/// only once the write succeeds, so a failed write leaves `path` as it was.
struct Staged {
    file: std::fs::File,
    staging: PathBuf,
    target: PathBuf,
}

fn create_staged(path: &str) -> Option<Staged> {
    let target =
        std::fs::canonicalize(path).unwrap_or_else(|_| PathBuf::from(path));
    let staging = staging_path(&target);
    let file = record(
        std::fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&staging)
            .map_err(|err| format!("cannot create file: {}", err)),
    )?;
    Some(Staged {
        file,
        staging,
        target,
    })
}

fn read_frame(
    path: *const c_char,
    read: impl FnOnce(std::fs::File) -> PolarsResult<DataFrame>,
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
    write: impl FnOnce(&mut std::fs::File, &mut DataFrame) -> PolarsResult<()>,
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
    let Some(Staged {
        mut file,
        staging,
        target,
    }) = create_staged(path_str)
    else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    let written = guard_panic(|| record(write(&mut file, df)));
    drop(file);
    let status = match written.map(|()| std::fs::rename(&staging, &target)) {
        Some(Ok(())) => IO_OK,
        Some(Err(err)) => {
            set_last_error(format!("cannot create file: {}", err));
            IO_OPEN_FAILED
        }
        None => IO_WRITE_FAILED,
    };
    if status != IO_OK {
        let _ = std::fs::remove_file(&staging);
    }
    status
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
