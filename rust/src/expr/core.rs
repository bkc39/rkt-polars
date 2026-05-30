use crate::prelude::*;

#[no_mangle]
pub extern "C" fn expr_drop(e: *mut Expr) {
    if !e.is_null() {
        unsafe { drop(Box::from_raw(e)) };
    }
}

#[no_mangle]
pub extern "C" fn expr_col(name: *const c_char) -> *mut Expr {
    if name.is_null() {
        return ptr::null_mut();
    }
    let n = match unsafe { CStr::from_ptr(name).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    Box::into_raw(Box::new(col(n)))
}

#[no_mangle]
pub extern "C" fn expr_lit_i32(v: i32) -> *mut Expr {
    Box::into_raw(Box::new(lit(v)))
}

#[no_mangle]
pub extern "C" fn expr_lit_i64(v: i64) -> *mut Expr {
    Box::into_raw(Box::new(lit(v)))
}

#[no_mangle]
pub extern "C" fn expr_lit_f64(v: f64) -> *mut Expr {
    Box::into_raw(Box::new(lit(v)))
}

#[no_mangle]
pub extern "C" fn expr_lit_bool(v: u8) -> *mut Expr {
    Box::into_raw(Box::new(lit(v != 0)))
}

#[no_mangle]
pub extern "C" fn expr_lit_str(v: *const c_char) -> *mut Expr {
    if v.is_null() {
        return ptr::null_mut();
    }
    let s = match unsafe { CStr::from_ptr(v).to_str() } {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };
    Box::into_raw(Box::new(lit(s)))
}

#[no_mangle]
pub extern "C" fn expr_alias(e: *const Expr, name: *const c_char) -> *mut Expr {
    if e.is_null() || name.is_null() {
        return ptr::null_mut();
    }
    let n = match unsafe { CStr::from_ptr(name).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let inner = unsafe { (*e).clone() };
    Box::into_raw(Box::new(inner.alias(n)))
}

/// Build a literal Expr from a Series (consumes nothing — clones the
/// Series). Useful as the right-hand side of `is_in`.
#[no_mangle]
pub extern "C" fn expr_lit_series(s: *const Series) -> *mut Expr {
    if s.is_null() {
        return ptr::null_mut();
    }
    let ss = unsafe { (*s).clone() };
    Box::into_raw(Box::new(lit(ss)))
}
