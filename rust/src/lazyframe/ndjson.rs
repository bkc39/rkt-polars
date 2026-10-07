use std::num::NonZeroUsize;

use crate::prelude::*;
use crate::{
    clear_last_error, decode_path, decode_schema, guard_panic,
    infer_schema_length, missing_override, read_path, record, without_plan,
    CompatDType, CompatNdjsonOptions, PathRules,
};

struct NdjsonArrays {
    schema_names: *const *const c_char,
    schema_dtypes: *const CompatDType,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
    row_index_name: *const c_char,
    include_file_paths: *const c_char,
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

fn row_index(
    options: &CompatNdjsonOptions,
    arrays: &NdjsonArrays,
) -> PolarsResult<Option<RowIndex>> {
    let Some(name) = decode_name(arrays.row_index_name, "row index name")?
    else {
        return Ok(None);
    };
    let offset = IdxSize::try_from(options.row_index_offset).map_err(
        |_| polars_err!(ComputeError: "row index offset {} is out of range", options.row_index_offset),
    )?;
    Ok(Some(RowIndex { name, offset }))
}

fn overridden(mut schema: Schema, overrides: &Schema) -> PolarsResult<Schema> {
    for (name, dtype) in overrides.iter() {
        *schema
            .try_get_mut(name)
            .map_err(|err| missing_override(err, "schema"))? = dtype.clone();
    }
    Ok(schema)
}

fn ndjson_scan(
    path: &str,
    options: &CompatNdjsonOptions,
    arrays: &NdjsonArrays,
) -> PolarsResult<LazyFrame> {
    let overrides = unsafe {
        decode_schema(
            arrays.override_names,
            arrays.override_dtypes,
            options.overrides_len,
            "override",
        )
    }?;
    let schema = if options.has_schema {
        let schema = unsafe {
            decode_schema(
                arrays.schema_names,
                arrays.schema_dtypes,
                options.schema_len,
                "schema",
            )
        }?;
        Some(Arc::new(overridden(schema, &overrides)?))
    } else {
        None
    };
    let has_overrides = schema.is_none() && !overrides.is_empty();
    let lf = LazyJsonLineReader::new(path.into())
        .with_infer_schema_length(infer_schema_length(
            options.has_infer_schema_length,
            options.infer_schema_length,
        )?)
        .with_batch_size(
            options
                .has_batch_size
                .then(|| NonZeroUsize::new(options.batch_size))
                .flatten(),
        )
        .with_n_rows(options.has_n_rows.then_some(options.n_rows))
        .low_memory(options.low_memory)
        .with_rechunk(options.rechunk)
        .with_schema(schema)
        .with_schema_overwrite(has_overrides.then(|| Arc::new(overrides)))
        .with_row_index(row_index(options, arrays)?)
        .with_ignore_errors(options.ignore_errors)
        .with_include_file_paths(decode_name(
            arrays.include_file_paths,
            "file paths column name",
        )?)
        .finish()?;
    if has_overrides {
        lf.clone()
            .collect_schema()
            .map_err(|err| without_plan(missing_override(err, "file")))?;
    }
    Ok(lf)
}

macro_rules! ndjson_entry {
    ($name:ident -> $out:ty, |$path:ident, $options:ident, $arrays:ident| $body:expr) => {
        #[no_mangle]
        #[allow(clippy::too_many_arguments)]
        pub extern "C" fn $name(
            $path: *const c_char,
            $options: CompatNdjsonOptions,
            schema_names: *const *const c_char,
            schema_dtypes: *const CompatDType,
            override_names: *const *const c_char,
            override_dtypes: *const CompatDType,
            row_index_name: *const c_char,
            include_file_paths: *const c_char,
        ) -> *mut $out {
            let $arrays = NdjsonArrays {
                schema_names,
                schema_dtypes,
                override_names,
                override_dtypes,
                row_index_name,
                include_file_paths,
            };
            $body
        }
    };
}

ndjson_entry!(lazyframe_scan_ndjson_with_options -> LazyFrame, |path, options, arrays| {
    clear_last_error();
    decode_path(path)
        .and_then(|path| guard_panic(|| record(ndjson_scan(path, &options, &arrays))))
        .map_or(ptr::null_mut(), |lf| Box::into_raw(Box::new(lf)))
});

ndjson_entry!(dataframe_read_ndjson_with_options -> DataFrame, |path, options, arrays| {
    read_path(
        path,
        PathRules {
            glob: true,
            directory: true,
        },
        |path| {
            ndjson_scan(path, &options, &arrays)
                .and_then(LazyFrame::collect)
                .map_err(without_plan)
        },
    )
});
