use crate::prelude::*;
use crate::{clear_last_error, decode_path, guard_panic, record};
use polars::io::HiveOptions;

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
    let args = ScanArgsParquet {
        n_rows,
        hive_options: HiveOptions {
            enabled: None,
            ..Default::default()
        },
        ..Default::default()
    };
    LazyFrame::scan_parquet(path.into(), args)
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
