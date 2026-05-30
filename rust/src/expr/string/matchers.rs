use crate::prelude::*;

#[no_mangle]
pub extern "C" fn expr_str_contains(
    e: *const Expr,
    pat: *const Expr,
    strict: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().contains(pp, strict != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_starts_with(
    e: *const Expr,
    prefix: *const Expr,
) -> *mut Expr {
    if e.is_null() || prefix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*prefix).clone() };
    Box::into_raw(Box::new(ee.str().starts_with(pp)))
}

#[no_mangle]
pub extern "C" fn expr_str_ends_with(
    e: *const Expr,
    suffix: *const Expr,
) -> *mut Expr {
    if e.is_null() || suffix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let ss = unsafe { (*suffix).clone() };
    Box::into_raw(Box::new(ee.str().ends_with(ss)))
}

#[no_mangle]
pub extern "C" fn expr_str_extract(
    e: *const Expr,
    pat: *const Expr,
    group_index: usize,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().extract(pp, group_index)))
}

#[no_mangle]
pub extern "C" fn expr_str_find(
    e: *const Expr,
    pat: *const Expr,
    strict: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().find(pp, strict != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_find_literal(
    e: *const Expr,
    pat: *const Expr,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().find_literal(pp)))
}

#[no_mangle]
pub extern "C" fn expr_str_count_matches(
    e: *const Expr,
    pat: *const Expr,
    literal: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().count_matches(pp, literal != 0)))
}
