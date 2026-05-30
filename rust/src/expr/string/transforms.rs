use crate::prelude::*;

#[no_mangle]
pub extern "C" fn expr_str_to_lowercase(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().to_lowercase()))
}

#[no_mangle]
pub extern "C" fn expr_str_to_uppercase(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().to_uppercase()))
}

#[no_mangle]
pub extern "C" fn expr_str_replace(
    e: *const Expr,
    pat: *const Expr,
    value: *const Expr,
    literal: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() || value.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    let vv = unsafe { (*value).clone() };
    Box::into_raw(Box::new(ee.str().replace(pp, vv, literal != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_replace_all(
    e: *const Expr,
    pat: *const Expr,
    value: *const Expr,
    literal: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() || value.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    let vv = unsafe { (*value).clone() };
    Box::into_raw(Box::new(ee.str().replace_all(pp, vv, literal != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars(
    e: *const Expr,
    chars: *const Expr,
) -> *mut Expr {
    if e.is_null() || chars.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let cc = unsafe { (*chars).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars(cc)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_start(
    e: *const Expr,
    chars: *const Expr,
) -> *mut Expr {
    if e.is_null() || chars.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let cc = unsafe { (*chars).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_start(cc)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_end(
    e: *const Expr,
    chars: *const Expr,
) -> *mut Expr {
    if e.is_null() || chars.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let cc = unsafe { (*chars).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_end(cc)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_whitespace(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars(Expr::default())))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_start_whitespace(
    e: *const Expr,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_start(Expr::default())))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_end_whitespace(
    e: *const Expr,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_end(Expr::default())))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_prefix(
    e: *const Expr,
    prefix: *const Expr,
) -> *mut Expr {
    if e.is_null() || prefix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*prefix).clone() };
    Box::into_raw(Box::new(ee.str().strip_prefix(pp)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_suffix(
    e: *const Expr,
    suffix: *const Expr,
) -> *mut Expr {
    if e.is_null() || suffix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let ss = unsafe { (*suffix).clone() };
    Box::into_raw(Box::new(ee.str().strip_suffix(ss)))
}
