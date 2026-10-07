use std::io::Write;
use std::num::NonZeroUsize;

use crate::prelude::*;
use crate::{
    clear_last_error, decode_path, decode_schema, guard_panic, record,
    write_frame, CompatDType, CompatJsonOptions,
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
