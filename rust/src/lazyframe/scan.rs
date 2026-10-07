use crate::prelude::*;
use crate::{
    clear_last_error, decode_path, guard_panic, record,
    CompatParquetReadOptions,
};
use polars::io::{HiveOptions, RowIndex};

pub(crate) fn scan(
    path: *const c_char,
    build: impl FnOnce(&str) -> PolarsResult<LazyFrame>,
) -> *mut LazyFrame {
    clear_last_error();
    decode_path(path)
        .and_then(|path| guard_panic(|| record(build(path))))
        .map_or(ptr::null_mut(), |lf| Box::into_raw(Box::new(lf)))
}

pub(crate) fn parquet_scan(
    path: &str,
    n_rows: Option<usize>,
) -> PolarsResult<LazyFrame> {
    let options = CompatParquetReadOptions {
        has_n_rows: n_rows.is_some(),
        n_rows: n_rows.unwrap_or(0),
        ..Default::default()
    };
    parquet_scan_with(path, &options, ParquetNames::default())
}

#[derive(Default)]
pub(crate) struct ParquetNames {
    pub row_index_name: Option<PlSmallStr>,
    pub include_file_paths: Option<PlSmallStr>,
}

fn decode_name(
    ptr: *const c_char,
    what: &str,
) -> PolarsResult<Option<PlSmallStr>> {
    if ptr.is_null() {
        return Ok(None);
    }
    let name = unsafe { CStr::from_ptr(ptr) }.to_str().map_err(
        |err| polars_err!(ComputeError: "{} is not valid UTF-8: {}", what, err),
    )?;
    Ok(Some(name.into()))
}

pub(crate) fn decode_parquet_names(
    row_index_name: *const c_char,
    include_file_paths: *const c_char,
) -> PolarsResult<ParquetNames> {
    Ok(ParquetNames {
        row_index_name: decode_name(row_index_name, "row index name")?,
        include_file_paths: decode_name(
            include_file_paths,
            "file path column name",
        )?,
    })
}

fn parallel_strategy(code: u8) -> PolarsResult<ParallelStrategy> {
    Ok(match code {
        0 => ParallelStrategy::Auto,
        1 => ParallelStrategy::Columns,
        2 => ParallelStrategy::RowGroups,
        3 => ParallelStrategy::Prefiltered,
        4 => ParallelStrategy::None,
        _ => polars_bail!(ComputeError: "unknown parallel strategy {}", code),
    })
}

pub(crate) fn parquet_scan_args(
    options: &CompatParquetReadOptions,
    names: ParquetNames,
) -> PolarsResult<ScanArgsParquet> {
    Ok(ScanArgsParquet {
        n_rows: options.has_n_rows.then_some(options.n_rows),
        parallel: parallel_strategy(options.parallel)?,
        row_index: names.row_index_name.map(|name| RowIndex {
            name,
            offset: options.row_index_offset as IdxSize,
        }),
        hive_options: HiveOptions {
            enabled: None,
            ..Default::default()
        },
        use_statistics: options.use_statistics,
        low_memory: options.low_memory,
        rechunk: options.rechunk,
        cache: options.cache,
        glob: options.glob,
        include_file_paths: names.include_file_paths,
        allow_missing_columns: options.allow_missing_columns,
        ..Default::default()
    })
}

pub(crate) fn parquet_scan_with(
    path: &str,
    options: &CompatParquetReadOptions,
    names: ParquetNames,
) -> PolarsResult<LazyFrame> {
    LazyFrame::scan_parquet(path.into(), parquet_scan_args(options, names)?)
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

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_with_options(
    path: *const c_char,
    options: CompatParquetReadOptions,
    row_index_name: *const c_char,
    include_file_paths: *const c_char,
) -> *mut LazyFrame {
    scan(path, |path| {
        let names = decode_parquet_names(row_index_name, include_file_paths)?;
        parquet_scan_with(path, &options, names)
    })
}
