use crate::prelude::*;
use crate::{
    collect_c_strings, is_pattern, polars_dtype_from_compat, read_path, scan,
    CompatCsvOptions, CompatDType, PathRules,
};

struct CsvArrays {
    comment_prefix: *const c_char,
    null_values: *const *const c_char,
    null_values_len: usize,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
    overrides_len: usize,
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
    Ok((!values.is_empty()).then(|| {
        NullValues::AllColumns(
            values.into_iter().map(PlSmallStr::from).collect(),
        )
    }))
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
                .map(|dtype| Field::new(name.into(), dtype))
                .ok_or_else(|| {
                    polars_err!(ComputeError: "unsupported dtype for column {:?}", name)
                })
        })
        .collect::<PolarsResult<Vec<_>>>()?;
    Ok(Some(Arc::new(Schema::from_iter(fields))))
}

struct CsvRequest {
    comment_prefix: Option<CommentPrefix>,
    null_values: Option<NullValues>,
    overrides: Option<SchemaRef>,
}

fn comment_prefix(prefix: String) -> CommentPrefix {
    match prefix.as_bytes() {
        [byte] if byte.is_ascii() => CommentPrefix::Single(*byte),
        _ => CommentPrefix::Multi(prefix.into()),
    }
}

fn decode(arrays: &CsvArrays) -> PolarsResult<CsvRequest> {
    Ok(CsvRequest {
        comment_prefix: decode_comment_prefix(arrays.comment_prefix)?
            .map(comment_prefix),
        null_values: decode_null_values(
            arrays.null_values,
            arrays.null_values_len,
        )?,
        overrides: decode_overrides(
            arrays.override_names,
            arrays.override_dtypes,
            arrays.overrides_len,
        )?,
    })
}

fn encoding(options: &CompatCsvOptions) -> CsvEncoding {
    if options.lossy_utf8 {
        CsvEncoding::LossyUtf8
    } else {
        CsvEncoding::Utf8
    }
}

fn parse_options(
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> CsvParseOptions {
    CsvParseOptions::default()
        .with_separator(options.separator)
        .with_quote_char(options.has_quote_char.then_some(options.quote_char))
        .with_comment_prefix(request.comment_prefix.clone())
        .with_encoding(encoding(options))
        .with_null_values(request.null_values.clone())
        .with_try_parse_dates(options.try_parse_dates)
}

fn read_options(
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> CsvReadOptions {
    CsvReadOptions::default()
        .with_has_header(options.has_header)
        .with_skip_rows(options.skip_rows)
        .with_n_rows(options.has_n_rows.then_some(options.n_rows))
        .with_infer_schema_length(
            options
                .has_infer_schema_length
                .then_some(options.infer_schema_length),
        )
        .with_ignore_errors(options.ignore_errors)
        .with_schema_overwrite(request.overrides.clone())
        .with_parse_options(parse_options(options, request))
}

fn lazy_reader(
    path: &str,
    options: &CompatCsvOptions,
    read: CsvReadOptions,
) -> LazyCsvReader {
    let parse = read.get_parse_options();
    LazyCsvReader::new(path.into())
        .with_glob(options.glob)
        .with_has_header(read.has_header)
        .with_skip_rows(read.skip_rows)
        .with_n_rows(read.n_rows)
        .with_infer_schema_length(read.infer_schema_length)
        .with_ignore_errors(read.ignore_errors)
        .with_dtype_overwrite(read.schema_overwrite)
        .map_parse_options(|_| (*parse).clone())
}

fn require_override_columns(
    path: &str,
    options: &CompatCsvOptions,
    request: &CsvRequest,
) -> PolarsResult<()> {
    let Some(overrides) = &request.overrides else {
        return Ok(());
    };
    let header = CsvReadOptions::default()
        .with_has_header(options.has_header)
        .with_skip_rows(options.skip_rows)
        .with_infer_schema_length(Some(0))
        .with_parse_options(parse_options(options, request));
    let names = lazy_reader(path, options, header)
        .finish()?
        .collect_schema()?;
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

fn csv_scan(
    path: &str,
    options: &CompatCsvOptions,
    arrays: &CsvArrays,
) -> PolarsResult<LazyFrame> {
    let request = decode(arrays)?;
    let lf =
        lazy_reader(path, options, read_options(options, &request)).finish()?;
    require_override_columns(path, options, &request)?;
    Ok(lf)
}

fn csv_read(
    path: &str,
    options: &CompatCsvOptions,
    arrays: &CsvArrays,
) -> PolarsResult<DataFrame> {
    if is_pattern(path, options.glob) {
        return csv_scan(path, options, arrays)?.collect();
    }
    let request = decode(arrays)?;
    require_override_columns(path, options, &request)?;
    read_options(options, &request)
        .try_into_reader_with_file_path(Some(path.into()))?
        .finish()
}

macro_rules! csv_entry {
    ($name:ident -> $out:ty, |$path:ident, $options:ident, $arrays:ident| $body:expr) => {
        #[no_mangle]
        #[allow(clippy::too_many_arguments)]
        pub extern "C" fn $name(
            $path: *const c_char,
            $options: CompatCsvOptions,
            comment_prefix: *const c_char,
            null_values: *const *const c_char,
            null_values_len: usize,
            override_names: *const *const c_char,
            override_dtypes: *const CompatDType,
            overrides_len: usize,
        ) -> *mut $out {
            let $arrays = CsvArrays {
                comment_prefix,
                null_values,
                null_values_len,
                override_names,
                override_dtypes,
                overrides_len,
            };
            $body
        }
    };
}

csv_entry!(lazyframe_scan_csv_with_options -> LazyFrame, |path, options, arrays| {
    scan(path, |path| csv_scan(path, &options, &arrays))
});

csv_entry!(dataframe_read_csv_with_options -> DataFrame, |path, options, arrays| {
    read_path(
        path,
        PathRules {
            glob: options.glob,
            directory: false,
        },
        |path| csv_read(path, &options, &arrays),
    )
});
