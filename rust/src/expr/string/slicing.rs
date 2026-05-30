use crate::prelude::*;

#[no_mangle]
pub extern "C" fn expr_str_len_bytes(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().len_bytes()))
}

#[no_mangle]
pub extern "C" fn expr_str_len_chars(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().len_chars()))
}

#[no_mangle]
pub extern "C" fn expr_str_slice(
    e: *const Expr,
    offset: *const Expr,
    length: *const Expr,
) -> *mut Expr {
    if e.is_null() || offset.is_null() || length.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let oo = unsafe { (*offset).clone() };
    let ll = unsafe { (*length).clone() };
    Box::into_raw(Box::new(ee.str().slice(oo, ll)))
}

#[no_mangle]
pub extern "C" fn expr_str_head(e: *const Expr, n: *const Expr) -> *mut Expr {
    if e.is_null() || n.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let nn = unsafe { (*n).clone() };
    Box::into_raw(Box::new(ee.str().head(nn)))
}

#[no_mangle]
pub extern "C" fn expr_str_tail(e: *const Expr, n: *const Expr) -> *mut Expr {
    if e.is_null() || n.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let nn = unsafe { (*n).clone() };
    Box::into_raw(Box::new(ee.str().tail(nn)))
}
