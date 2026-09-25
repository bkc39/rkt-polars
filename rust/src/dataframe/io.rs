use crate::prelude::*;
use crate::*;
use polars::prelude::{SerReader, SerWriter};

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

fn create_file(path: &str) -> Option<std::fs::File> {
    record(
        std::fs::File::create(path)
            .map_err(|err| format!("cannot create file: {}", err)),
    )
}

fn read_frame(
    path: *const c_char,
    read: impl FnOnce(std::fs::File) -> PolarsResult<DataFrame>,
) -> *mut DataFrame {
    clear_last_error();
    decode_path(path)
        .and_then(open_file)
        .and_then(|file| record(read(file)))
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
}

fn require_file(path: &str, glob: bool) -> PolarsResult<()> {
    if glob && path.contains(['*', '?', '[']) {
        return Ok(());
    }
    std::fs::metadata(path)
        .map(|_| ())
        .map_err(|err| polars_err!(ComputeError: "cannot open file: {}", err))
}

fn collect_frame(
    path: *const c_char,
    glob: bool,
    build: impl FnOnce(&str) -> PolarsResult<LazyFrame>,
) -> *mut DataFrame {
    clear_last_error();
    decode_path(path)
        .and_then(|path| {
            record(
                require_file(path, glob)
                    .and_then(|()| build(path))
                    .and_then(LazyFrame::collect),
            )
        })
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
}

fn write_frame(
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
    let Some(mut file) = create_file(path_str) else {
        return IO_OPEN_FAILED;
    };
    let df = unsafe { &mut *df_ptr };
    match record(write(&mut file, df)) {
        Some(()) => IO_OK,
        None => IO_WRITE_FAILED,
    }
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
#[allow(clippy::too_many_arguments)]
pub extern "C" fn dataframe_read_csv_with_options(
    path: *const c_char,
    options: CompatCsvOptions,
    comment_prefix: *const c_char,
    null_values: *const *const c_char,
    null_values_len: usize,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
    overrides_len: usize,
) -> *mut DataFrame {
    let arrays = CsvArrays {
        comment_prefix,
        null_values,
        null_values_len,
        override_names,
        override_dtypes,
        overrides_len,
    };
    collect_frame(path, options.glob != 0, |path| {
        csv_scan(path, &options, &arrays)
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
    collect_frame(path, true, |path| parquet_scan(path, None))
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
