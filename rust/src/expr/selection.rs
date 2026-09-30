use crate::prelude::*;
use crate::*;

// ----- sorting / selection helpers -----

expr_unop!(expr_reverse, |e| e.reverse());
expr_binop!(expr_filter, |a, b| a.filter(b));
expr_binop!(expr_gather, |a, b| a.gather(b, false));

#[no_mangle]
pub extern "C" fn expr_sort_by_with_options(
    e: *const Expr,
    by: *const *const Expr,
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let opts = match unsafe {
        sort_multiple_options(descending, nulls_last, n, maintain_order)
    } {
        Ok(o) => o,
        Err(_) => return ptr::null_mut(),
    };
    let by_vec = match unsafe { collect_exprs(by, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let ee = unsafe { (*e).clone() };
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
    Box::into_raw(Box::new(
        ee.fill_null_with_strategy(FillNullStrategy::Forward(lim)),
    ))
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
    Box::into_raw(Box::new(
        ee.fill_null_with_strategy(FillNullStrategy::Backward(lim)),
    ))
}

#[no_mangle]
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
    match inner.over(parts) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn expr_sort_with_options(
    e: *const Expr,
    descending: u8,
    nulls_last: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let inner = unsafe { (*e).clone() };
    let opts = SortOptions::default()
        .with_order_descending(descending != 0)
        .with_nulls_last(nulls_last != 0);
    let sorted = if is_scalar(&inner) {
        inner
    } else {
        inner.sort(opts)
    };
    Box::into_raw(Box::new(sorted))
}

/// Whether `e` yields one value, per group in `agg` or `over`, from its
/// structure alone. Polars 0.55.2's `SortExpr` sorts such an input by
/// gathering each group's row indices from the one value per group, which
/// reads out of bounds, so the sort of one is the input itself.
fn is_scalar(e: &Expr) -> bool {
    match e {
        Expr::Agg(_) | Expr::Len => true,
        Expr::Gather { returns_scalar, .. } => *returns_scalar,
        Expr::Literal(value) => value.is_scalar(),
        Expr::Alias(inner, _)
        | Expr::KeepName(inner)
        | Expr::RenameAlias { expr: inner, .. }
        | Expr::Cast { expr: inner, .. }
        | Expr::Sort { expr: inner, .. } => is_scalar(inner),
        Expr::BinaryExpr { left, right, .. } => {
            is_scalar(left) && is_scalar(right)
        }
        Expr::Ternary {
            predicate,
            truthy,
            falsy,
        } => is_scalar(predicate) && is_scalar(truthy) && is_scalar(falsy),
        _ => false,
    }
}

// LazyGroupBy::agg consumes self and LazyGroupBy is not Clone, which
// breaks the Racket allocator/deallocator round-tripping pattern.  Fold
// group_by + agg into a single FFI call so the intermediate state never
// crosses the boundary.
