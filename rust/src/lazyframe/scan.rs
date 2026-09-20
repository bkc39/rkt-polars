use crate::prelude::*;
use crate::{clear_last_error, record, set_last_error};

/// Decode a scan path, recording why it was unusable.
///
/// Every scan reports failure the same way — a null `LazyFrame` — so unlike the
/// writers in `dataframe::io` there is no status ladder to preserve here, and a
/// null pointer and bad UTF-8 can share one helper.
fn scan_path<'a>(op: &str, path: *const c_char) -> Option<&'a str> {
    if path.is_null() {
        set_last_error(format!("{}: path is null", op));
        return None;
    }
    match unsafe { CStr::from_ptr(path) }.to_str() {
        Ok(s) => Some(s),
        Err(err) => {
            set_last_error(format!("{}: path is not valid UTF-8: {}", op, err));
            None
        }
    }
}

/// Box a scan result, recording the reason when the scan failed.
fn finish_scan(
    op: &str,
    path: &str,
    scanned: PolarsResult<LazyFrame>,
) -> *mut LazyFrame {
    match record(&format!("{} {}", op, path), scanned) {
        Some(lf) => Box::into_raw(Box::new(lf)),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_csv(path: *const c_char) -> *mut LazyFrame {
    const OP: &str = "scan csv";
    clear_last_error();
    let Some(path_str) = scan_path(OP, path) else {
        return ptr::null_mut();
    };
    finish_scan(
        OP,
        path_str,
        polars::prelude::LazyCsvReader::new(path_str).finish(),
    )
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
    const OP: &str = "scan csv";
    clear_last_error();
    let Some(path_str) = scan_path(OP, path) else {
        return ptr::null_mut();
    };
    let mut reader = polars::prelude::LazyCsvReader::new(path_str)
        .with_has_header(has_header != 0)
        .with_separator(separator)
        .with_skip_rows(skip_rows);
    if has_n_rows != 0 {
        reader = reader.with_n_rows(Some(n_rows));
    }
    finish_scan(OP, path_str, reader.finish())
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet(
    path: *const c_char,
) -> *mut LazyFrame {
    const OP: &str = "scan parquet";
    clear_last_error();
    let Some(path_str) = scan_path(OP, path) else {
        return ptr::null_mut();
    };
    finish_scan(
        OP,
        path_str,
        LazyFrame::scan_parquet(path_str, Default::default()),
    )
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_options(
    path: *const c_char,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    const OP: &str = "scan parquet";
    clear_last_error();
    let Some(path_str) = scan_path(OP, path) else {
        return ptr::null_mut();
    };
    let mut args = ScanArgsParquet::default();
    if has_n_rows != 0 {
        args.n_rows = Some(n_rows);
    }
    finish_scan(OP, path_str, LazyFrame::scan_parquet(path_str, args))
}
