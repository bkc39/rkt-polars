use crate::prelude::*;

use super::strings::{str_list_arg, StrListArg};

/// The `len` elements at `data`; `data` may be NULL only when `len` is 0.
///
/// # Safety
/// A non-NULL `data` points to `len` initialised elements that outlive `'a`.
pub(crate) unsafe fn slice_or_empty<'a, T>(
    data: *const T,
    len: usize,
) -> Option<&'a [T]> {
    match (len, data.is_null()) {
        (0, _) => Some(&[]),
        (_, true) => None,
        (_, false) => Some(std::slice::from_raw_parts(data, len)),
    }
}

pub(crate) unsafe fn collect_c_strings(
    ptrs: *const *const c_char,
    n: usize,
) -> Option<Vec<String>> {
    let slice = slice_or_empty(ptrs, n)?;
    let mut out = Vec::with_capacity(n);
    for &p in slice {
        if p.is_null() {
            return None;
        }
        match CStr::from_ptr(p).to_str() {
            Ok(s) => out.push(s.to_string()),
            Err(_) => return None,
        }
    }
    Some(out)
}

pub(crate) unsafe fn collect_exprs(
    ptrs: *const *const Expr,
    n: usize,
) -> Option<Vec<Expr>> {
    let slice = slice_or_empty(ptrs, n)?;
    let mut out = Vec::with_capacity(n);
    for &p in slice {
        if p.is_null() {
            return None;
        }
        out.push((*p).clone());
    }
    Some(out)
}

unsafe fn collect_flags(
    ptr: *const u8,
    n: usize,
    what: &'static str,
) -> Result<Vec<bool>, &'static str> {
    if ptr.is_null() {
        return Err(what);
    }
    Ok(std::slice::from_raw_parts(ptr, n)
        .iter()
        .map(|&b| b != 0)
        .collect())
}

/// Zero keys is an error: polars reads the first key's flags unchecked.
pub(crate) unsafe fn sort_multiple_options(
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> Result<SortMultipleOptions, &'static str> {
    if n == 0 {
        return Err("sort needs at least one key");
    }
    let descending = collect_flags(descending, n, "descending flags are null")?;
    let nulls_last = collect_flags(nulls_last, n, "nulls-last flags are null")?;
    Ok(SortMultipleOptions::new()
        .with_order_descending_multi(descending)
        .with_nulls_last_multi(nulls_last)
        .with_maintain_order(maintain_order != 0))
}

/// The keys of a sort by name, checked against the flags' count, and its
/// options.
///
/// # Safety
/// As for `str_list_arg`; `descending` and `nulls_last` point to `n` flags.
pub(crate) unsafe fn named_sort<'a>(
    by: StrListArg,
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> PolarsResult<(Vec<&'a str>, SortMultipleOptions)> {
    let opts = sort_multiple_options(descending, nulls_last, n, maintain_order)
        .map_err(|cause| polars_err!(ComputeError: "{}", cause))?;
    let names = str_list_arg(by)?;
    polars_ensure!(
        names.len() == n,
        ComputeError: "{} sort keys but {} flags", names.len(), n
    );
    Ok((names, opts))
}
