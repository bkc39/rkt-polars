use crate::prelude::*;
use crate::{
    collect_c_strings, collect_frame, polars_dtype_from_compat, require_files,
    scan, CompatCsvOptions, CompatDType, PathRules,
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

fn parse_reader(
    path: &str,
    options: &CompatCsvOptions,
    comment_prefix: Option<&str>,
) -> LazyCsvReader {
    LazyCsvReader::new(path)
        .with_glob(options.glob)
        .with_has_header(options.has_header)
        .with_separator(options.separator)
        .with_quote_char(options.has_quote_char.then_some(options.quote_char))
        .with_comment_prefix(comment_prefix)
        .with_skip_rows(options.skip_rows)
        .with_encoding(if options.lossy_utf8 {
            CsvEncoding::LossyUtf8
        } else {
            CsvEncoding::Utf8
        })
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

fn csv_scan(
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
        .with_n_rows(options.has_n_rows.then_some(options.n_rows))
        .with_infer_schema_length(
            options
                .has_infer_schema_length
                .then_some(options.infer_schema_length),
        )
        .with_null_values(null_values)
        .with_dtype_overwrite(overrides.clone())
        .with_ignore_errors(options.ignore_errors)
        .with_try_parse_dates(options.try_parse_dates)
        .finish()
        .and_then(require_files)?;
    if let Some(overrides) = &overrides {
        require_override_columns(reader, overrides)?;
    }
    Ok(lf)
}

macro_rules! csv_entry {
    ($name:ident -> $out:ty, |$path:ident, $options:ident, $scan:ident| $body:expr) => {
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
            let arrays = CsvArrays {
                comment_prefix,
                null_values,
                null_values_len,
                override_names,
                override_dtypes,
                overrides_len,
            };
            let $scan = |path: &str| csv_scan(path, &$options, &arrays);
            $body
        }
    };
}

csv_entry!(lazyframe_scan_csv_with_options -> LazyFrame, |path, options, csv| {
    scan(path, csv)
});

csv_entry!(dataframe_read_csv_with_options -> DataFrame, |path, options, csv| {
    collect_frame(
        path,
        PathRules {
            glob: options.glob,
            directory: false,
        },
        csv,
    )
});
