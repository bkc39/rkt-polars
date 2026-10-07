use crate::prelude::*;
use crate::{collect_c_strings, polars_dtype_from_compat, CompatDType};

/// The `len` column names and dtypes a caller passed as a schema; `what`
/// names the argument in an error.
pub(crate) unsafe fn decode_schema(
    names: *const *const c_char,
    dtypes: *const CompatDType,
    len: usize,
    what: &str,
) -> PolarsResult<Schema> {
    if len == 0 {
        return Ok(Schema::default());
    }
    let names = collect_c_strings(names, len).ok_or_else(
        || polars_err!(ComputeError: "{} names are not valid UTF-8 strings", what),
    )?;
    polars_ensure!(!dtypes.is_null(), ComputeError: "{} dtypes are null", what);
    let dtypes = std::slice::from_raw_parts(dtypes, len);
    names
        .iter()
        .zip(dtypes)
        .map(|(name, dtype)| {
            polars_dtype_from_compat(dtype)
                .map(|dtype| Field::new(name.into(), dtype))
                .ok_or_else(|| {
                    polars_err!(ComputeError: "unsupported dtype for column {:?}", name)
                })
        })
        .collect()
}
