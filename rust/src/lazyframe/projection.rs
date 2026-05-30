use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_with_columns(
    lf: *mut LazyFrame,
    expr_ptrs: *const *const Expr,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let exprs = match unsafe { collect_exprs(expr_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.with_columns(exprs)))
}

#[no_mangle]
pub extern "C" fn lazyframe_filter(
    lf: *mut LazyFrame,
    predicate: *const Expr,
) -> *mut LazyFrame {
    if lf.is_null() || predicate.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    let p = unsafe { (*predicate).clone() };
    Box::into_raw(Box::new(lf_ref.filter(p)))
}

#[no_mangle]
pub extern "C" fn lazyframe_select(
    lf: *mut LazyFrame,
    expr_ptrs: *const *const Expr,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let exprs = match unsafe { collect_exprs(expr_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.select(exprs)))
}
