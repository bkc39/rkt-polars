use crate::prelude::*;

#[no_mangle]
pub extern "C" fn lazyframe_unique(lf: *mut LazyFrame) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(
        lf_ref.unique(None, polars::prelude::UniqueKeepStrategy::Any),
    ))
}

#[no_mangle]
pub extern "C" fn lazyframe_drop_nulls(lf: *mut LazyFrame) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    let subset: Option<Vec<Expr>> = None;
    Box::into_raw(Box::new(lf_ref.drop_nulls(subset)))
}

// ===== Phase A7: lazy head / tail / slice =====

#[no_mangle]
pub extern "C" fn lazyframe_head(
    lf: *mut LazyFrame,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.limit(n as u32)))
}

#[no_mangle]
pub extern "C" fn lazyframe_tail(
    lf: *mut LazyFrame,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.tail(n as u32)))
}

#[no_mangle]
pub extern "C" fn lazyframe_slice(
    lf: *mut LazyFrame,
    offset: i64,
    length: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.slice(offset, length as u32)))
}

// ===== Phase A8: lazy join =====
//
// Mirrors the eager `dataframe_join` ABI exactly: same `CompatJoinKind`
// tags, same packed left/right key-name arrays.  Cross uses
// `LazyFrame::cross_join`; inner/left/outer go through `.join` with
// per-side `Vec<Expr>` built from `col(name)`.
