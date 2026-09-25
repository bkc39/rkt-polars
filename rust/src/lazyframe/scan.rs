use crate::prelude::*;
use crate::{clear_last_error, decode_path, record};

fn scan(
    path: *const c_char,
    build: impl FnOnce(&str) -> PolarsResult<LazyFrame>,
) -> *mut LazyFrame {
    clear_last_error();
    decode_path(path)
        .and_then(|path| record(build(path)))
        .map_or(ptr::null_mut(), |lf| Box::into_raw(Box::new(lf)))
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_csv(path: *const c_char) -> *mut LazyFrame {
    scan(path, |path| LazyCsvReader::new(path).finish())
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_csv_options(
    path: *const c_char,
    has_header: u8,
    separator: u8,
    skip_rows: usize,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    scan(path, |path| {
        let reader = LazyCsvReader::new(path)
            .with_has_header(has_header != 0)
            .with_separator(separator)
            .with_skip_rows(skip_rows);
        let reader = if has_n_rows != 0 {
            reader.with_n_rows(Some(n_rows))
        } else {
            reader
        };
        reader.finish()
    })
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet(
    path: *const c_char,
) -> *mut LazyFrame {
    scan(path, |path| {
        LazyFrame::scan_parquet(path, Default::default())
    })
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_options(
    path: *const c_char,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    scan(path, |path| {
        let mut args = ScanArgsParquet::default();
        if has_n_rows != 0 {
            args.n_rows = Some(n_rows);
        }
        LazyFrame::scan_parquet(path, args)
    })
}
