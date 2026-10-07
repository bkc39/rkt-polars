use crate::prelude::*;
use crate::{
    clear_last_error, collect_c_strings, collect_frame, decode_parquet_names,
    parquet_scan_with, record, write_frame, CompatParquetReadOptions,
    CompatParquetWriteOptions, PathRules,
};
use polars::polars_utils::compression::{BrotliLevel, GzipLevel, ZstdLevel};

const IO_BAD_OPTIONS: i32 = 5;

const COLUMNS_ALL: u8 = 0;
const COLUMNS_BY_NAME: u8 = 1;
const COLUMNS_BY_INDEX: u8 = 2;

pub(crate) enum ColumnSelection {
    Names(Vec<String>),
    Indices(Vec<i64>),
}

pub(crate) fn decode_columns(
    kind: u8,
    names: *const *const c_char,
    indices: *const i64,
    len: usize,
) -> PolarsResult<Option<ColumnSelection>> {
    let selection = match kind {
        COLUMNS_ALL => return Ok(None),
        COLUMNS_BY_NAME => unsafe { collect_c_strings(names, len) }
            .map(ColumnSelection::Names)
            .ok_or_else(
                || polars_err!(ComputeError: "column names are not valid UTF-8 strings"),
            )?,
        COLUMNS_BY_INDEX if len == 0 => ColumnSelection::Indices(Vec::new()),
        COLUMNS_BY_INDEX => {
            polars_ensure!(!indices.is_null(), ComputeError: "column indices are null");
            ColumnSelection::Indices(
                unsafe { std::slice::from_raw_parts(indices, len) }.to_vec(),
            )
        },
        _ => polars_bail!(ComputeError: "unknown column selection {}", kind),
    };
    Ok(Some(selection))
}

fn resolve_index(index: i64, schema: &Schema) -> PolarsResult<String> {
    let width = schema.len() as i64;
    let position = if index < 0 { index + width } else { index };
    (0..width)
        .contains(&position)
        .then(|| schema.get_at_index(position as usize))
        .flatten()
        .map(|(name, _)| name.to_string())
        .ok_or_else(|| {
            polars_err!(
                ComputeError: "column index {} is out of range for {} columns",
                index, width
            )
        })
}

fn selected_names(
    selection: ColumnSelection,
    schema: &Schema,
) -> PolarsResult<Vec<String>> {
    let names = match selection {
        ColumnSelection::Names(names) => {
            let missing: Vec<String> = names
                .iter()
                .filter(|name| !schema.contains(name))
                .map(|name| format!("{:?}", name))
                .collect();
            polars_ensure!(
                missing.is_empty(),
                ComputeError: "columns not in the file: {}",
                missing.join(", ")
            );
            names
        }
        ColumnSelection::Indices(indices) => indices
            .into_iter()
            .map(|index| resolve_index(index, schema))
            .collect::<PolarsResult<Vec<_>>>()?,
    };
    let mut seen = PlHashSet::new();
    if let Some(twice) = names.iter().find(|name| !seen.insert(name.as_str())) {
        polars_bail!(ComputeError: "column {:?} is selected more than once", twice);
    }
    Ok(names)
}

pub(crate) fn select_columns(
    mut lf: LazyFrame,
    selection: Option<ColumnSelection>,
) -> PolarsResult<LazyFrame> {
    let Some(selection) = selection else {
        return Ok(lf);
    };
    let schema = lf.collect_schema()?;
    let names = selected_names(selection, &schema)?;
    Ok(lf.select(
        names
            .into_iter()
            .map(|name| Expr::Column(name.into()))
            .collect::<Vec<_>>(),
    ))
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn dataframe_read_parquet_with_options(
    path: *const c_char,
    options: CompatParquetReadOptions,
    row_index_name: *const c_char,
    include_file_paths: *const c_char,
    columns_kind: u8,
    column_names: *const *const c_char,
    column_indices: *const i64,
    columns_len: usize,
) -> *mut DataFrame {
    collect_frame(
        path,
        PathRules {
            glob: options.glob,
            directory: true,
        },
        |path| {
            let names =
                decode_parquet_names(row_index_name, include_file_paths)?;
            let selection = decode_columns(
                columns_kind,
                column_names,
                column_indices,
                columns_len,
            )?;
            select_columns(parquet_scan_with(path, &options, names)?, selection)
        },
    )
}

fn level<T>(
    options: &CompatParquetWriteOptions,
    codec: &str,
    make: impl FnOnce(i32) -> PolarsResult<T>,
) -> PolarsResult<Option<T>> {
    let level = options.compression_level;
    options
        .has_compression_level
        .then(|| {
            make(level).map_err(|err| {
                polars_err!(
                    ComputeError: "compression level {} is out of range for {}: {}",
                    level, codec, err
                )
            })
        })
        .transpose()
}

pub(crate) fn parquet_compression(
    options: &CompatParquetWriteOptions,
) -> PolarsResult<ParquetCompression> {
    Ok(match options.compression {
        0 => ParquetCompression::Uncompressed,
        1 => ParquetCompression::Snappy,
        2 => ParquetCompression::Gzip(level(options, "gzip", |l| {
            GzipLevel::try_new(u8::try_from(l).unwrap_or(u8::MAX))
        })?),
        3 => ParquetCompression::Brotli(level(options, "brotli", |l| {
            BrotliLevel::try_new(u32::try_from(l).unwrap_or(u32::MAX))
        })?),
        4 => ParquetCompression::Lz4Raw,
        5 => ParquetCompression::Zstd(level(
            options,
            "zstd",
            ZstdLevel::try_new,
        )?),
        code => polars_bail!(ComputeError: "unknown compression {}", code),
    })
}

pub(crate) fn parquet_write_options(
    options: &CompatParquetWriteOptions,
) -> PolarsResult<ParquetWriteOptions> {
    let bit = |n: u8| options.statistics & (1 << n) != 0;
    Ok(ParquetWriteOptions {
        compression: parquet_compression(options)?,
        statistics: StatisticsOptions {
            min_value: bit(0),
            max_value: bit(1),
            distinct_count: bit(2),
            null_count: bit(3),
            ..StatisticsOptions::empty()
        },
        row_group_size: options
            .has_row_group_size
            .then_some(options.row_group_size)
            .filter(|&rows| rows > 0),
        data_page_size: options
            .has_data_page_size
            .then_some(options.data_page_size),
        ..Default::default()
    })
}

fn write_parquet(
    file: &mut std::fs::File,
    df: &mut DataFrame,
    options: &ParquetWriteOptions,
) -> PolarsResult<()> {
    let writer = options.to_writer(file);
    let Some(rows) = options.row_group_size else {
        return writer.finish(df).map(|_| ());
    };
    let mut batched = writer.batched(df.schema())?;
    for offset in (0..df.height()).step_by(rows) {
        let mut group = df.slice(offset as i64, rows);
        group.rechunk_mut_par();
        batched.write_batch(&group)?;
    }
    batched.finish().map(|_| ())
}

#[no_mangle]
pub extern "C" fn dataframe_write_parquet_with_options(
    df_ptr: *mut DataFrame,
    path: *const c_char,
    options: CompatParquetWriteOptions,
) -> i32 {
    clear_last_error();
    let Some(write_options) = record(parquet_write_options(&options)) else {
        return IO_BAD_OPTIONS;
    };
    write_frame(df_ptr, path, |file, df| {
        write_parquet(file, df, &write_options)
    })
}
