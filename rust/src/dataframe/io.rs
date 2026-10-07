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

fn create_file(path: &Path) -> Option<std::fs::File> {
    record(
        std::fs::File::create(path)
            .map_err(|err| format!("cannot create file: {}", err)),
    )
}

static TEMP_FILES: AtomicUsize = AtomicUsize::new(0);

/// A writer writes here and `finish_replacing` renames it onto `target`, so
/// a failed write leaves an existing file as it was. The name keeps
/// `target`'s extensions, which polars' sinks check.
pub(crate) fn temp_sibling(target: &Path) -> PathBuf {
    let name = target
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    target.with_file_name(format!(
        ".rkt-polars-{}-{}-{}",
        std::process::id(),
        TEMP_FILES.fetch_add(1, Ordering::Relaxed),
        name
    ))
}

pub(crate) fn finish_replacing(
    temp: &Path,
    target: &Path,
    written: Option<()>,
) -> i32 {
    let renamed = written.and_then(|()| {
        record(
            std::fs::rename(temp, target)
                .map_err(|err| format!("cannot create file: {}", err)),
        )
    });
    match renamed {
        Some(()) => IO_OK,
        None => {
            let _ = std::fs::remove_file(temp);
            IO_WRITE_FAILED
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
    let target = Path::new(path_str);
    let temp = temp_sibling(target);
    let Some(mut file) = create_file(&temp) else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    let written = guard_panic(|| record(write(&mut file, df)));
    drop(file);
    finish_replacing(&temp, target, written)
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
