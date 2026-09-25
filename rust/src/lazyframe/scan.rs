use crate::prelude::*;
use crate::{
    clear_last_error, collect_c_strings, decode_path, polars_dtype_from_compat,
    record, CompatCsvOptions, CompatDType,
};
use polars::io::HiveOptions;

fn scan(
    path: *const c_char,
    build: impl FnOnce(&str) -> PolarsResult<LazyFrame>,
) -> *mut LazyFrame {
    clear_last_error();
    decode_path(path)
        .and_then(|path| record(build(path)))
        .map_or(ptr::null_mut(), |lf| Box::into_raw(Box::new(lf)))
}

pub(crate) struct CsvArrays {
    pub comment_prefix: *const c_char,
    pub null_values: *const *const c_char,
    pub null_values_len: usize,
    pub override_names: *const *const c_char,
    pub override_dtypes: *const CompatDType,
    pub overrides_len: usize,
}

fn decode_comment_prefix(ptr: *const c_char) -> PolarsResult<Option<String>> {
    if ptr.is_null() {
        return Ok(None);
    }
    let prefix = unsafe { CStr::from_ptr(ptr) }.to_str().map_err(
        |err| polars_err!(ComputeError: "comment prefix is not valid UTF-8: {}", err),
    )?;
    Ok(Some(prefix.to_string()))
}

fn decode_null_values(
    ptrs: *const *const c_char,
    len: usize,
) -> PolarsResult<Option<NullValues>> {
    let values = unsafe { collect_c_strings(ptrs, len) }.ok_or_else(
        || polars_err!(ComputeError: "null values are not valid UTF-8 strings"),
    )?;
    Ok((!values.is_empty()).then_some(NullValues::AllColumns(values)))
}

fn decode_overrides(
    names: *const *const c_char,
    dtypes: *const CompatDType,
    len: usize,
) -> PolarsResult<Option<SchemaRef>> {
    if len == 0 {
        return Ok(None);
    }
    let names = unsafe { collect_c_strings(names, len) }.ok_or_else(
        || polars_err!(ComputeError: "override names are not valid UTF-8 strings"),
    )?;
    polars_ensure!(
        !dtypes.is_null(),
        ComputeError: "override dtypes are null"
    );
    let dtypes = unsafe { std::slice::from_raw_parts(dtypes, len) };
    let fields = names
        .iter()
        .zip(dtypes)
        .map(|(name, dtype)| {
            polars_dtype_from_compat(dtype)
                .map(|dtype| Field::new(name, dtype))
                .ok_or_else(|| {
                    polars_err!(ComputeError: "unsupported dtype for column {:?}", name)
                })
        })
        .collect::<PolarsResult<Vec<_>>>()?;
    Ok(Some(Arc::new(Schema::from_iter(fields))))
}

fn flag(b: u8) -> bool {
    b != 0
}

fn parse_reader(
    path: &str,
    options: &CompatCsvOptions,
    comment_prefix: Option<&str>,
) -> LazyCsvReader {
    LazyCsvReader::new(path)
        .with_glob(flag(options.glob))
        .with_has_header(flag(options.has_header))
        .with_separator(options.separator)
        .with_quote_char(
            flag(options.has_quote_char).then_some(options.quote_char),
        )
        .with_comment_prefix(comment_prefix)
        .with_skip_rows(options.skip_rows)
        .with_encoding(if flag(options.lossy_utf8) {
            CsvEncoding::LossyUtf8
        } else {
            CsvEncoding::Utf8
        })
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

fn require_override_columns(
    header: LazyCsvReader,
    overrides: &Schema,
) -> PolarsResult<()> {
    let names = header
        .with_infer_schema_length(Some(0))
        .finish()?
        .schema()?;
    let missing: Vec<String> = overrides
        .iter_names()
        .filter(|name| !names.contains(name))
        .map(|name| format!("{:?}", name.as_str()))
        .collect();
    polars_ensure!(
        missing.is_empty(),
        ComputeError: "schema overrides name columns not in the file: {}",
        missing.join(", ")
    );
    Ok(())
}

pub(crate) fn csv_scan(
    path: &str,
    options: &CompatCsvOptions,
    arrays: &CsvArrays,
) -> PolarsResult<LazyFrame> {
    let comment_prefix = decode_comment_prefix(arrays.comment_prefix)?;
    let null_values =
        decode_null_values(arrays.null_values, arrays.null_values_len)?;
    let overrides = decode_overrides(
        arrays.override_names,
        arrays.override_dtypes,
        arrays.overrides_len,
    )?;
    let reader = parse_reader(path, options, comment_prefix.as_deref());
    let lf = reader
        .clone()
        .with_n_rows(flag(options.has_n_rows).then_some(options.n_rows))
        .with_infer_schema_length(
            flag(options.has_infer_schema_length)
                .then_some(options.infer_schema_length),
        )
        .with_null_values(null_values)
        .with_dtype_overwrite(overrides.clone())
        .with_ignore_errors(flag(options.ignore_errors))
        .with_try_parse_dates(flag(options.try_parse_dates))
        .finish()
        .and_then(require_files)?;
    if let Some(overrides) = &overrides {
        require_override_columns(reader, overrides)?;
    }
    Ok(lf)
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub extern "C" fn lazyframe_scan_csv_with_options(
    path: *const c_char,
    options: CompatCsvOptions,
    comment_prefix: *const c_char,
    null_values: *const *const c_char,
    null_values_len: usize,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
    overrides_len: usize,
) -> *mut LazyFrame {
    let arrays = CsvArrays {
        comment_prefix,
        null_values,
        null_values_len,
        override_names,
        override_dtypes,
        overrides_len,
    };
    scan(path, |path| csv_scan(path, &options, &arrays))
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
        parquet_scan(path, flag(has_n_rows).then_some(n_rows))
    })
}
