use crate::prelude::*;
use crate::slice_or_empty;

/// The `length` values at `data`, refused when `data` is NULL with rows.
///
/// # Safety
/// As for `slice_or_empty`.
pub(crate) unsafe fn values_arg<'a, T: 'a>(
    data: *const T,
    length: usize,
) -> PolarsResult<&'a [T]> {
    slice_or_empty(data, length).ok_or_else(|| {
        polars_err!(
            ComputeError: "the values are null but {} rows were given", length
        )
    })
}

/// The values at `data`, each `None` where `valid` holds 0.
///
/// # Safety
/// As for `slice_or_empty`, for both `data` and `valid`.
pub(crate) unsafe fn optional_values<'a, T: 'a>(
    data: *const T,
    valid: *const u8,
    length: usize,
) -> PolarsResult<impl Iterator<Item = Option<&'a T>>> {
    let values = values_arg(data, length)?;
    let valid = slice_or_empty(valid, length).ok_or_else(|| {
        polars_err!(
            ComputeError: "the validity flags are null but {} rows were given",
            length
        )
    })?;
    Ok(values
        .iter()
        .zip(valid)
        .map(|(value, is_valid)| (*is_valid != 0).then_some(value)))
}
