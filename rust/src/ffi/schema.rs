use crate::prelude::*;
use crate::{polars_dtype_from_compat, str_list_arg, CompatDType, StrListArg};

/// The `len` column names and dtypes a caller passed as a schema; `what`
/// names the argument in an error.
pub(crate) fn decode_schema(
    names: StrListArg,
    dtypes: *const CompatDType,
    len: usize,
    what: &str,
) -> PolarsResult<Schema> {
    let names = unsafe { str_list_arg(names) }?;
    polars_ensure!(
        names.len() == len,
        ComputeError: "{} {} names are given for {} dtypes",
        names.len(),
        what,
        len
    );
    if len == 0 {
        return Ok(Schema::default());
    }
    polars_ensure!(!dtypes.is_null(), ComputeError: "{} dtypes are null", what);
    let dtypes = unsafe { std::slice::from_raw_parts(dtypes, len) };
    names
        .iter()
        .zip(dtypes)
        .map(|(name, dtype)| {
            polars_dtype_from_compat(dtype)
                .map(|dtype| Field::new(PlSmallStr::from(*name), dtype))
                .ok_or_else(|| {
                    polars_err!(ComputeError: "unsupported dtype for column {:?}", name)
                })
        })
        .collect()
}
