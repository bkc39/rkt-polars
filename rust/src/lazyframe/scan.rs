use crate::prelude::*;
use crate::{
    clear_last_error, decode_path, guard_panic, optional_name, record,
    CompatParquetReadOptions, StrArg,
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

#[derive(Default)]
pub(crate) struct ParquetNames {
    pub row_index_name: Option<PlSmallStr>,
    pub include_file_paths: Option<PlSmallStr>,
}

pub(crate) fn decode_parquet_names(
    row_index_name: StrArg,
    include_file_paths: StrArg,
) -> PolarsResult<ParquetNames> {
    Ok(ParquetNames {
        row_index_name: optional_name(row_index_name)?,
        include_file_paths: optional_name(include_file_paths)?,
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
    let args = parquet_scan_args(options, names)?;
    let row_index = args.row_index.clone();
    let lf = LazyFrame::scan_parquet(
        path.into(),
        ScanArgsParquet {
            row_index: zero_based(&row_index),
            ..args
        },
    )?;
    Ok(offset_rows(lf, &row_index))
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_with_options_v2(
    path: *const c_char,
    options: CompatParquetReadOptions,
    row_index_name: StrArg,
    include_file_paths: StrArg,
) -> *mut LazyFrame {
    scan(path, |path| {
        let names = decode_parquet_names(row_index_name, include_file_paths)?;
        parquet_scan_with(path, &options, names)
    })
}

/// The row index a reader numbers from zero; `offset_rows` and
/// `offset_frame_rows` add the offset afterwards, checked, because polars'
/// readers add it unchecked (eager CSV wraps, the streaming node panics).
pub(crate) fn zero_based(row_index: &Option<RowIndex>) -> Option<RowIndex> {
    row_index.as_ref().map(|ri| RowIndex {
        name: ri.name.clone(),
        offset: 0,
    })
}

fn offset_column(column: Column, offset: IdxSize) -> PolarsResult<Column> {
    let index = column.idx()?;
    if index
        .max()
        .is_some_and(|last| last.checked_add(offset).is_none())
    {
        polars_bail!(
            ComputeError: "row index from offset {offset} overflows {IDX_DTYPE}"
        );
    }
    Ok((index + offset).into_column())
}

pub(crate) fn offset_rows(
    lf: LazyFrame,
    row_index: &Option<RowIndex>,
) -> LazyFrame {
    match row_index {
        Some(RowIndex { name, offset }) if *offset > 0 => {
            let offset = *offset;
            lf.with_column(col(name.clone()).map(
                move |column| offset_column(column, offset),
                |_, field| Ok(field.clone()),
            ))
        }
        _ => lf,
    }
}

pub(crate) fn offset_frame_rows(
    mut df: DataFrame,
    row_index: &Option<RowIndex>,
) -> PolarsResult<DataFrame> {
    match row_index {
        Some(RowIndex { name, offset }) if *offset > 0 => {
            let shifted = offset_column(df.column(name)?.clone(), *offset)?;
            df.with_column(shifted)?;
            Ok(df)
        }
        _ => Ok(df),
    }
}
