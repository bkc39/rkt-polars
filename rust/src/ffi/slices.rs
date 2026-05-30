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
