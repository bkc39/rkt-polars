use crate::prelude::*;

pub extern "C" fn lazyframe_scan_csv(path: *const c_char) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match polars::prelude::LazyCsvReader::new(path_str).finish() {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
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
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let mut reader = polars::prelude::LazyCsvReader::new(path_str)
        .with_has_header(has_header != 0)
        .with_separator(separator)
        .with_skip_rows(skip_rows);
    if has_n_rows != 0 {
        reader = reader.with_n_rows(Some(n_rows));
    }
    match reader.finish() {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet(
    path: *const c_char,
) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match LazyFrame::scan_parquet(path_str, Default::default()) {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_options(
    path: *const c_char,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let mut args = ScanArgsParquet::default();
    if has_n_rows != 0 {
        args.n_rows = Some(n_rows);
    }
    match LazyFrame::scan_parquet(path_str, args) {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}
