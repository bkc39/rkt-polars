use crate::prelude::*;
use crate::*;

/// Status codes shared by the writers.  The reason for the failure is recorded
/// alongside, and read back with `last_error_message`.
const IO_OK: i32 = 0;
const IO_NULL_ARG: i32 = 1;
const IO_BAD_PATH: i32 = 2;
const IO_OPEN_FAILED: i32 = 3;
const IO_WRITE_FAILED: i32 = 4;

/// Decode a caller-supplied path, recording why it was unusable.
///
/// The recorded message names only the reason: the Racket wrapper already
/// reports which operation failed and on which path, so repeating either here
/// would double it up in the final message.
fn path_str<'a>(path: *const c_char) -> Option<&'a str> {
    match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => Some(s),
        Err(err) => {
            set_last_error(format!("path is not valid UTF-8: {}", err));
            None
        }
    }
}

/// Open `path` for writing, recording the OS reason on failure.
fn create_file(path: &str) -> Option<std::fs::File> {
    record("cannot create file", std::fs::File::create(path))
}

/// Open `path` for reading, recording the OS reason on failure.
fn open_file(path: &str) -> Option<std::fs::File> {
    record("cannot open file", std::fs::File::open(path))
}

/// Check the arguments every writer takes, recording which one was null.
fn writer_args(df_ptr: *mut DataFrame, path: *const c_char) -> Option<()> {
    if df_ptr.is_null() {
        set_last_error("dataframe is null");
        return None;
    }
    if path.is_null() {
        set_last_error("path is null");
        return None;
    }
    Some(())
}

/// Check the single argument every reader takes.
fn reader_args(path: *const c_char) -> Option<()> {
    if path.is_null() {
        set_last_error("path is null");
        return None;
    }
    Some(())
}

#[no_mangle]
pub extern "C" fn dataframe_write_csv(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    const OP: &str = "csv writer";
    clear_last_error();
    if writer_args(df_ptr, path).is_none() {
        return IO_NULL_ARG;
    }
    let Some(path_str) = path_str(path) else {
        return IO_BAD_PATH;
    };
    let Some(mut file) = create_file(path_str) else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    use polars::prelude::SerWriter;
    let written = polars::prelude::CsvWriter::new(&mut file)
        .include_header(true)
        .with_separator(b',')
        .finish(df);
    match record(OP, written) {
        Some(_) => IO_OK,
        None => IO_WRITE_FAILED,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_read_csv(path: *const c_char) -> *mut DataFrame {
    const OP: &str = "csv reader";
    clear_last_error();
    if reader_args(path).is_none() {
        return ptr::null_mut();
    }
    let Some(path_str) = path_str(path) else {
        return ptr::null_mut();
    };
    let Some(file) = open_file(path_str) else {
        return ptr::null_mut();
    };
    use polars::prelude::SerReader;
    let parsed = polars::prelude::CsvReadOptions::default()
        .with_has_header(true)
        .into_reader_with_file_handle(file)
        .finish();
    match record(OP, parsed) {
        Some(df) => Box::into_raw(Box::new(df)),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_write_parquet(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    const OP: &str = "parquet writer";
    clear_last_error();
    if writer_args(df_ptr, path).is_none() {
        return IO_NULL_ARG;
    }
    let Some(path_str) = path_str(path) else {
        return IO_BAD_PATH;
    };
    let Some(mut file) = create_file(path_str) else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    let written = polars::prelude::ParquetWriter::new(&mut file).finish(df);
    match record(OP, written) {
        Some(_) => IO_OK,
        None => IO_WRITE_FAILED,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_read_parquet(
    path: *const c_char,
) -> *mut DataFrame {
    const OP: &str = "parquet reader";
    clear_last_error();
    if reader_args(path).is_none() {
        return ptr::null_mut();
    }
    let Some(path_str) = path_str(path) else {
        return ptr::null_mut();
    };
    let Some(file) = open_file(path_str) else {
        return ptr::null_mut();
    };
    let parsed = polars::prelude::ParquetReader::new(file).finish();
    match record(OP, parsed) {
        Some(df) => Box::into_raw(Box::new(df)),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_write_json_lines(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    const OP: &str = "ndjson writer";
    clear_last_error();
    if writer_args(df_ptr, path).is_none() {
        return IO_NULL_ARG;
    }
    let Some(path_str) = path_str(path) else {
        return IO_BAD_PATH;
    };
    let Some(mut file) = create_file(path_str) else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    use polars::prelude::SerWriter;
    let written = polars::prelude::JsonWriter::new(&mut file)
        .with_json_format(polars::prelude::JsonFormat::JsonLines)
        .finish(df);
    match record(OP, written) {
        Some(_) => IO_OK,
        None => IO_WRITE_FAILED,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_read_json_lines(
    path: *const c_char,
) -> *mut DataFrame {
    const OP: &str = "ndjson reader";
    clear_last_error();
    if reader_args(path).is_none() {
        return ptr::null_mut();
    }
    let Some(path_str) = path_str(path) else {
        return ptr::null_mut();
    };
    let Some(file) = open_file(path_str) else {
        return ptr::null_mut();
    };
    use polars::prelude::SerReader;
    let parsed = polars::prelude::JsonReader::new(file)
        .with_json_format(polars::prelude::JsonFormat::JsonLines)
        .finish();
    match record(OP, parsed) {
        Some(df) => Box::into_raw(Box::new(df)),
        None => ptr::null_mut(),
    }
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
