use std::fs::{File, OpenOptions};
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::prelude::*;
use crate::*;
use polars::prelude::SerWriter;

const IO_OK: i32 = 0;
const IO_NULL_ARG: i32 = 1;
const IO_BAD_PATH: i32 = 2;
const IO_OPEN_FAILED: i32 = 3;
const IO_WRITE_FAILED: i32 = 4;
pub(crate) const IO_BAD_OPTIONS: i32 = 5;

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
/// `target`, or the target itself when it is not a regular file.
pub(crate) enum Staged {
    Replace {
        file: File,
        staging: PathBuf,
        target: PathBuf,
    },
    InPlace(File),
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
    let kept = permissions
        .map_or(Ok(()), |permissions| file.set_permissions(permissions));
    let staged = Staged::Replace {
        file,
        staging,
        target,
    };
    match kept {
        Ok(()) => Ok(staged),
        Err(err) => {
            staged.finish(None);
            Err(cannot_create(err))
        }
    }
}

fn in_place(target: PathBuf) -> Result<Staged, String> {
    File::create(target)
        .map(Staged::InPlace)
        .map_err(cannot_create)
}

fn stage_existing(target: PathBuf) -> Result<Staged, String> {
    match std::fs::metadata(&target) {
        Err(err) if err.kind() == ErrorKind::NotFound => stage(target, None),
        Err(err) => Err(cannot_create(err)),
        Ok(meta) if meta.is_dir() => {
            Err("cannot create file: it is a directory".to_string())
        }
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

pub(crate) fn create_staged(path: &str) -> Result<Staged, String> {
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
    fn file(&mut self) -> &mut File {
        match self {
            Staged::Replace { file, .. } | Staged::InPlace(file) => file,
        }
    }

    pub(crate) fn finish(self, written: Option<()>) -> i32 {
        match self {
            Staged::InPlace(_) => written.map_or(IO_WRITE_FAILED, |()| IO_OK),
            Staged::Replace {
                file,
                staging,
                target,
            } => {
                drop(file);
                let renamed = written.and_then(|()| {
                    record(
                        std::fs::rename(&staging, &target)
                            .map_err(cannot_create),
                    )
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
    }
}

pub(crate) struct PathRules {
    pub glob: bool,
    pub directory: bool,
}

pub(crate) fn is_pattern(path: &str, glob: bool) -> bool {
    glob && path.contains(['*', '?', '['])
}

pub(crate) fn require_path(path: &str, rules: &PathRules) -> PolarsResult<()> {
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
    write_checked_frame(
        df_ptr,
        path,
        |_, _| Ok(()),
        |(), file, df| write(file, df),
    )
}

/// `check` runs before the target is opened; what it returns is handed to
/// `write`.
pub(crate) fn write_checked_frame<T>(
    df_ptr: *mut DataFrame,
    path: *const c_char,
    check: impl FnOnce(&str, &DataFrame) -> PolarsResult<T>,
    write: impl FnOnce(T, &mut File, &mut DataFrame) -> PolarsResult<()>,
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
    let df = unsafe { &mut *df_ptr };
    let Some(checked) = guard_panic(|| record(check(path_str, df))) else {
        return IO_WRITE_FAILED;
    };
    let Some(mut staged) = record(create_staged(path_str)) else {
        return IO_OPEN_FAILED;
    };
    let written = guard_panic(|| record(write(checked, staged.file(), df)));
    staged.finish(written)
}

fn optional_str(
    ptr: *const c_char,
    what: &str,
) -> PolarsResult<Option<PlSmallStr>> {
    if ptr.is_null() {
        return Ok(None);
    }
    let text = unsafe { CStr::from_ptr(ptr) }.to_str().map_err(
        |err| polars_err!(ComputeError: "{} is not valid UTF-8: {}", what, err),
    )?;
    Ok(Some(text.into()))
}

fn quote_style(code: u8) -> PolarsResult<QuoteStyle> {
    Ok(match code {
        0 => QuoteStyle::Necessary,
        1 => QuoteStyle::Always,
        2 => QuoteStyle::NonNumeric,
        3 => QuoteStyle::Never,
        _ => polars_bail!(ComputeError: "unknown quote style {}", code),
    })
}

pub(crate) struct CsvWriteStrings {
    pub(crate) line_terminator: *const c_char,
    pub(crate) null_value: *const c_char,
    pub(crate) datetime_format: *const c_char,
    pub(crate) date_format: *const c_char,
    pub(crate) time_format: *const c_char,
}

pub(crate) fn csv_writer<W: std::io::Write>(
    out: W,
    options: &CompatCsvWriteOptions,
    strings: &CsvWriteStrings,
    height: usize,
) -> PolarsResult<CsvWriter<W>> {
    let batch_size =
        std::num::NonZeroUsize::new(options.batch_size.min(height.max(1)))
            .ok_or_else(
                || polars_err!(ComputeError: "batch size must be positive"),
            )?;
    polars_ensure!(
        !options.has_float_precision
            || options.float_precision <= u16::MAX as usize,
        ComputeError: "float precision {} is over {}",
        options.float_precision,
        u16::MAX
    );
    let line_terminator =
        optional_str(strings.line_terminator, "line terminator")?
            .unwrap_or_else(|| "\n".into());
    let null_value =
        optional_str(strings.null_value, "null value")?.unwrap_or_default();
    Ok(CsvWriter::new(out)
        .include_header(options.include_header)
        .include_bom(options.include_bom)
        .with_separator(options.separator)
        .with_quote_char(options.quote_char)
        .with_quote_style(quote_style(options.quote_style)?)
        .with_line_terminator(line_terminator)
        .with_null_value(null_value)
        .with_batch_size(batch_size)
        .with_datetime_format(optional_str(
            strings.datetime_format,
            "datetime format",
        )?)
        .with_date_format(optional_str(strings.date_format, "date format")?)
        .with_time_format(optional_str(strings.time_format, "time format")?)
        .with_float_scientific(
            options
                .has_float_scientific
                .then_some(options.float_scientific),
        )
        .with_float_precision(
            options
                .has_float_precision
                .then_some(options.float_precision),
        )
        .with_decimal_comma(options.decimal_comma))
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn dataframe_write_csv_with_options(
    df_ptr: *mut DataFrame,
    path: *const c_char,
    options: CompatCsvWriteOptions,
    line_terminator: *const c_char,
    null_value: *const c_char,
    datetime_format: *const c_char,
    date_format: *const c_char,
    time_format: *const c_char,
) -> i32 {
    let strings = CsvWriteStrings {
        line_terminator,
        null_value,
        datetime_format,
        date_format,
        time_format,
    };
    write_frame(df_ptr, path, |file, df| {
        csv_writer(file, &options, &strings, df.height())?.finish(df)
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
