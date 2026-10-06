use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn expr_cast(e: *mut Expr, target: CompatDType) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let dt = match polars_dtype_from_compat(&target) {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    let e_ref = unsafe { (*e).clone() };
    Box::into_raw(Box::new(e_ref.cast(dt)))
}

#[no_mangle]
pub extern "C" fn expr_cast_enum(
    e: *const Expr,
    categories: *const *const c_char,
    n: usize,
) -> *mut Expr {
    clear_last_error();
    let Some(e) = (unsafe { e.as_ref() }) else {
        set_last_error("expression is null");
        return ptr::null_mut();
    };
    enum_dtype(categories, n).map_or(ptr::null_mut(), |dtype| {
        Box::into_raw(Box::new(e.clone().strict_cast(dtype)))
    })
}

#[no_mangle]
pub extern "C" fn expr_cast_datetime_tz(
    e: *const Expr,
    unit: i32,
    tz: *const c_char,
) -> *mut Expr {
    clear_last_error();
    let Some(e) = (unsafe { e.as_ref() }) else {
        set_last_error("expression is null");
        return ptr::null_mut();
    };
    datetime_tz_dtype(unit, tz).map_or(ptr::null_mut(), |dtype| {
        Box::into_raw(Box::new(e.clone().cast(dtype)))
    })
}
