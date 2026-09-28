use crate::prelude::*;

pub(crate) unsafe fn collect_c_strings(
    ptrs: *const *const c_char,
    n: usize,
) -> Option<Vec<String>> {
    if n == 0 {
        return Some(Vec::new());
    }
    if ptrs.is_null() {
        return None;
    }
    let slice = std::slice::from_raw_parts(ptrs, n);
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
    if n == 0 {
        return Some(Vec::new());
    }
    if ptrs.is_null() {
        return None;
    }
    let slice = std::slice::from_raw_parts(ptrs, n);
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
