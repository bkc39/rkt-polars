use crate::prelude::*;
use crate::*;

// ----- sorting / selection helpers -----

expr_unop!(expr_reverse, |e| e.reverse());
expr_binop!(expr_filter, |a, b| a.filter(b));
expr_binop!(expr_gather, |a, b| a.gather(b));

/// sort_by parallel `by` exprs + `descending` flags (length `n`).
#[no_mangle]
pub extern "C" fn expr_sort_by(
    e: *const Expr,
    by: *const *const Expr,
    descending: *const u8,
    n: usize,
) -> *mut Expr {
    if e.is_null() || by.is_null() || descending.is_null() || n == 0 {
        return ptr::null_mut();
    }
    let by = unsafe { std::slice::from_raw_parts(by, n) };
    let desc = unsafe { std::slice::from_raw_parts(descending, n) };
    if by.iter().any(|p| p.is_null()) {
        return ptr::null_mut();
    }
    let by_vec: Vec<Expr> =
        by.iter().map(|p| unsafe { (**p).clone() }).collect();
    let desc_vec: Vec<bool> = desc.iter().map(|b| *b != 0).collect();
    let ee = unsafe { (*e).clone() };
    let opts =
        SortMultipleOptions::default().with_order_descending_multi(desc_vec);
    Box::into_raw(Box::new(ee.sort_by(by_vec, opts)))
}

/// rank with `method` (0 average, 1 min, 2 max, 3 dense, 4 ordinal),
/// `descending`, and an optional `seed`.
#[no_mangle]
pub extern "C" fn expr_rank(
    e: *const Expr,
    method: u8,
    descending: u8,
    has_seed: u8,
    seed: u64,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let m = match method {
        1 => RankMethod::Min,
        2 => RankMethod::Max,
        3 => RankMethod::Dense,
        4 => RankMethod::Ordinal,
        _ => RankMethod::Average,
    };
    let ee = unsafe { (*e).clone() };
    let opts = RankOptions {
        method: m,
        descending: descending != 0,
    };
    let s = if has_seed != 0 { Some(seed) } else { None };
    Box::into_raw(Box::new(ee.rank(opts, s)))
}

#[no_mangle]
pub extern "C" fn expr_head(
    e: *const Expr,
    has_len: u8,
    len: usize,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let n = if has_len != 0 { Some(len) } else { None };
    Box::into_raw(Box::new(ee.head(n)))
}

#[no_mangle]
pub extern "C" fn expr_tail(
    e: *const Expr,
    has_len: u8,
    len: usize,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let n = if has_len != 0 { Some(len) } else { None };
    Box::into_raw(Box::new(ee.tail(n)))
}

#[no_mangle]
pub extern "C" fn expr_slice(
    e: *const Expr,
    offset: i64,
    length: i64,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.slice(lit(offset), lit(length))))
}

#[no_mangle]
pub extern "C" fn expr_forward_fill(
    e: *const Expr,
    has_limit: u8,
    limit: u32,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lim = if has_limit != 0 { Some(limit) } else { None };
    Box::into_raw(Box::new(ee.forward_fill(lim)))
}

#[no_mangle]
pub extern "C" fn expr_backward_fill(
    e: *const Expr,
    has_limit: u8,
    limit: u32,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lim = if has_limit != 0 { Some(limit) } else { None };
    Box::into_raw(Box::new(ee.backward_fill(lim)))
}

pub extern "C" fn expr_over(
    e: *const Expr,
    partition_ptrs: *const *const Expr,
    n: usize,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let parts = match unsafe { collect_exprs(partition_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let inner = unsafe { (*e).clone() };
    Box::into_raw(Box::new(inner.over(parts)))
}

#[no_mangle]
pub extern "C" fn expr_sort(e: *const Expr, descending: u8) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let inner = unsafe { (*e).clone() };
    let opts = SortOptions::default().with_order_descending(descending != 0);
    Box::into_raw(Box::new(inner.sort(opts)))
}

// LazyGroupBy::agg consumes self and LazyGroupBy is not Clone, which
// breaks the Racket allocator/deallocator round-tripping pattern.  Fold
// group_by + agg into a single FFI call so the intermediate state never
// crosses the boundary.
