use std::io::Write;
use std::num::NonZeroUsize;

use crate::prelude::*;
use crate::{
    clear_last_error, decode_path, decode_schema, guard_panic, record,
    set_last_error, write_frame, CompatDType, CompatJsonOptions, IO_BAD_PATH,
    IO_NULL_ARG, IO_OK, IO_WRITE_FAILED,
};
use polars::prelude::{SerReader, SerWriter};

struct JsonArrays {
    schema_names: *const *const c_char,
    schema_dtypes: *const CompatDType,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
}

pub(crate) fn infer_schema_length(
    given: bool,
    rows: usize,
) -> PolarsResult<Option<NonZeroUsize>> {
    if !given {
        return Ok(None);
    }
    NonZeroUsize::new(rows).map(Some).ok_or_else(
        || polars_err!(ComputeError: "infer schema length must be positive"),
    )
}

fn json_file(path: &str) -> PolarsResult<std::fs::File> {
    let open_err = |err| polars_err!(ComputeError: "cannot open file: {}", err);
    let file = std::fs::File::open(path).map_err(open_err)?;
    let metadata = file.metadata().map_err(open_err)?;
    polars_ensure!(
        !metadata.is_dir(),
        ComputeError: "cannot open file: it is a directory"
    );
    Ok(file)
}

pub(crate) fn missing_override(err: PolarsError, against: &str) -> PolarsError {
    match err {
        PolarsError::SchemaFieldNotFound(name) => polars_err!(
            ComputeError: "schema overrides name a column not in the {}: {:?}",
            against,
            name.as_ref()
        ),
        err => err,
    }
}

fn json_read(
    path: &str,
    options: &CompatJsonOptions,
    arrays: &JsonArrays,
) -> PolarsResult<DataFrame> {
    let schema = if options.has_schema {
        Some(unsafe {
            decode_schema(
                arrays.schema_names,
                arrays.schema_dtypes,
                options.schema_len,
                "schema",
            )
        }?)
    } else {
        None
    };
    let overrides = unsafe {
        decode_schema(
            arrays.override_names,
            arrays.override_dtypes,
            options.overrides_len,
            "override",
        )
    }?;
    let mut reader = JsonReader::new(json_file(path)?)
        .with_json_format(JsonFormat::Json)
        .infer_schema_len(infer_schema_length(
            options.has_infer_schema_length,
            options.infer_schema_length,
        )?);
    if let Some(schema) = schema {
        reader = reader.with_schema(Arc::new(schema));
    }
    if overrides.is_empty() {
        return reader.finish();
    }
    let against = if options.has_schema { "schema" } else { "file" };
    reader
        .with_schema_overwrite(&overrides)
        .finish()
        .map_err(|err| missing_override(err, against))
}

#[no_mangle]
pub extern "C" fn dataframe_read_json_with_options(
    path: *const c_char,
    options: CompatJsonOptions,
    schema_names: *const *const c_char,
    schema_dtypes: *const CompatDType,
    override_names: *const *const c_char,
    override_dtypes: *const CompatDType,
) -> *mut DataFrame {
    let arrays = JsonArrays {
        schema_names,
        schema_dtypes,
        override_names,
        override_dtypes,
    };
    clear_last_error();
    decode_path(path)
        .and_then(|path| {
            guard_panic(|| record(json_read(path, &options, &arrays)))
        })
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
}

fn holds_binary(dtype: &DataType) -> bool {
    match dtype {
        DataType::Binary | DataType::BinaryOffset => true,
        DataType::List(inner) => holds_binary(inner),
        DataType::Struct(fields) => {
            fields.iter().any(|field| holds_binary(field.dtype()))
        }
        _ => false,
    }
}

pub(crate) fn refuse_binary(df: &DataFrame) -> PolarsResult<()> {
    match df
        .columns()
        .iter()
        .find(|column| holds_binary(column.dtype()))
    {
        Some(column) => Err(polars_err!(
            ComputeError: "cannot write the binary column {:?} as JSON",
            column.name().as_str()
        )),
        None => Ok(()),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_write_json(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    write_frame(df_ptr, path, |file, df| {
        refuse_binary(df)?;
        let mut buffer = std::io::BufWriter::new(file);
        JsonWriter::new(&mut buffer)
            .with_json_format(JsonFormat::Json)
            .finish(df)?;
        buffer.flush()?;
        Ok(())
    })
}

pub(crate) fn without_plan(err: PolarsError) -> PolarsError {
    err.wrap_msg(|msg| {
        msg.split("\n\nResolved plan until failure:")
            .next()
            .unwrap_or(msg)
            .to_string()
    })
}

fn ndjson_compression(
    code: u8,
    level: Option<u32>,
) -> PolarsResult<ExternalCompression> {
    match code {
        0 => Ok(ExternalCompression::Uncompressed),
        1 => Ok(ExternalCompression::Gzip { level }),
        2 => Ok(ExternalCompression::Zstd { level }),
        _ => Err(polars_err!(ComputeError: "unknown compression {}", code)),
    }
}

fn ndjson_write(
    df: &DataFrame,
    path: &str,
    options: NDJsonWriterOptions,
) -> PolarsResult<()> {
    df.clone()
        .lazy()
        .sink(
            SinkDestination::File {
                target: SinkTarget::Path(path.into()),
            },
            FileWriteFormat::NDJson(options),
            UnifiedSinkArgs::default(),
        )?
        .collect()
        .map(drop)
        .map_err(without_plan)
}

#[no_mangle]
pub extern "C" fn dataframe_write_ndjson_with_options(
    df_ptr: *mut DataFrame,
    path: *const c_char,
    compression: u8,
    has_compression_level: bool,
    compression_level: u32,
    check_extension: bool,
) -> i32 {
    clear_last_error();
    if df_ptr.is_null() {
        set_last_error("dataframe is null");
        return IO_NULL_ARG;
    }
    let Some(path) = decode_path(path) else {
        return IO_BAD_PATH;
    };
    let df = unsafe { &*df_ptr };
    let level = has_compression_level.then_some(compression_level);
    let written = guard_panic(|| {
        record(
            ndjson_compression(compression, level).and_then(|compression| {
                ndjson_write(
                    df,
                    path,
                    NDJsonWriterOptions {
                        compression,
                        check_extension,
                    },
                )
            }),
        )
    });
    match written {
        Some(()) => IO_OK,
        None => IO_WRITE_FAILED,
    }
}
