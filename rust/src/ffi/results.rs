use crate::prelude::*;

use super::errors::{clear_last_error, guard_panic, record};

/// `f`'s value, boxed for the caller to drop, or NULL with the error or
/// panic recorded.
pub(crate) fn boxed_result<T>(f: impl FnOnce() -> PolarsResult<T>) -> *mut T {
    clear_last_error();
    guard_panic(|| record(f()))
        .map_or(ptr::null_mut(), |value| Box::into_raw(Box::new(value)))
}

/// `f`'s value, or `failed` with the error or panic recorded.
pub(crate) fn scalar_result<T>(
    failed: T,
    f: impl FnOnce() -> PolarsResult<T>,
) -> T {
    clear_last_error();
    guard_panic(|| record(f())).unwrap_or(failed)
}

/// `f` of the series `s_ptr` points to, as `scalar_result`.
pub(crate) fn with_series<T>(
    s_ptr: *const Series,
    failed: T,
    f: impl FnOnce(&Series) -> PolarsResult<T>,
) -> T {
    scalar_result(failed, || f(unsafe { deref_arg(s_ptr, "series") }?))
}

/// As `boxed_result`, for an entry point that runs no polars code on the
/// caller's data.
pub(crate) fn boxed_unguarded<T>(
    f: impl FnOnce() -> PolarsResult<T>,
) -> *mut T {
    clear_last_error();
    record(f()).map_or(ptr::null_mut(), |value| Box::into_raw(Box::new(value)))
}

/// # Safety
/// A non-NULL `p` points to a live `T` that outlives `'a`.
pub(crate) unsafe fn deref_arg<'a, T>(
    p: *const T,
    what: &str,
) -> PolarsResult<&'a T> {
    unsafe { p.as_ref() }
        .ok_or_else(|| polars_err!(ComputeError: "{} is null", what))
}

/// # Safety
/// A non-NULL `p` points to a live `T` that outlives `'a` and that nothing
/// else reads or writes meanwhile.
pub(crate) unsafe fn deref_mut_arg<'a, T>(
    p: *mut T,
    what: &str,
) -> PolarsResult<&'a mut T> {
    unsafe { p.as_mut() }
        .ok_or_else(|| polars_err!(ComputeError: "{} is null", what))
}
