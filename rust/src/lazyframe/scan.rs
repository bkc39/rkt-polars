use crate::prelude::*;
use crate::{clear_last_error, decode_path, record};
use polars::io::HiveOptions;

pub(crate) fn scan(
    path: *const c_char,
    build: impl FnOnce(&str) -> PolarsResult<LazyFrame>,
) -> *mut LazyFrame {
    clear_last_error();
    decode_path(path)
        .and_then(|path| record(build(path)))
        .map_or(ptr::null_mut(), |lf| Box::into_raw(Box::new(lf)))
}

pub(crate) fn require_files(lf: LazyFrame) -> PolarsResult<LazyFrame> {
    if let DslPlan::Scan { paths, .. } = &lf.logical_plan {
        polars_ensure!(
            !paths.is_empty(),
            ComputeError: "no files match the pattern"
        );
    }
    Ok(lf)
}

pub(crate) fn parquet_scan(
    path: &str,
    n_rows: Option<usize>,
) -> PolarsResult<LazyFrame> {
    let args = ScanArgsParquet {
        n_rows,
        hive_options: HiveOptions {
            enabled: None,
            ..Default::default()
        },
        ..Default::default()
    };
    LazyFrame::scan_parquet(path, args).and_then(require_files)
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet(
    path: *const c_char,
) -> *mut LazyFrame {
    scan(path, |path| parquet_scan(path, None))
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_options(
    path: *const c_char,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    scan(path, |path| {
        parquet_scan(path, (has_n_rows != 0).then_some(n_rows))
    })
}
