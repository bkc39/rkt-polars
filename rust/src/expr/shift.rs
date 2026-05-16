use crate::prelude::*;

#[no_mangle]
pub extern "C" fn expr_shift(e: *const Expr, n: i64) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.shift(lit(n))))
}

#[no_mangle]
pub extern "C" fn expr_shift_and_fill(
    e: *const Expr,
    n: i64,
    fill_value: *const Expr,
) -> *mut Expr {
    if e.is_null() || fill_value.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let fv = unsafe { (*fill_value).clone() };
    Box::into_raw(Box::new(ee.shift_and_fill(lit(n), fv)))
}

/// `diff` with a `null_behavior` selector: 0 = ignore (default), 1 = drop.
#[no_mangle]
pub extern "C" fn expr_diff(
    e: *const Expr,
    n: i64,
    null_behavior: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let nb = if null_behavior == 1 {
        polars::series::ops::NullBehavior::Drop
    } else {
        polars::series::ops::NullBehavior::Ignore
    };
    Box::into_raw(Box::new(ee.diff(n, nb)))
}
