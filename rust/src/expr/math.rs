use crate::prelude::*;

// ----- element-wise math -----

expr_unop!(expr_abs, |e| e.abs());
expr_unop!(expr_sign, |e| e.sign());
expr_unop!(expr_floor, |e| e.floor());
expr_unop!(expr_ceil, |e| e.ceil());
expr_unop!(expr_sqrt, |e| e.sqrt());
expr_unop!(expr_exp, |e| e.exp());
expr_unop!(expr_log1p, |e| e.log1p());
expr_unop_u32!(expr_round, |e, decimals| e.round(decimals));
expr_binop!(expr_pow, |a, b| a.pow(b));

#[no_mangle]
pub extern "C" fn expr_log(e: *const Expr, base: f64) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.log(base)))
}

/// Clip values into `[min, max]`. Either bound may be absent (`has_*` == 0),
/// in which case the one-sided `clip_min` / `clip_max` is used (or the
/// identity expression when both are absent).
#[no_mangle]
pub extern "C" fn expr_clip(
    e: *const Expr,
    has_min: u8,
    min: *const Expr,
    has_max: u8,
    max: *const Expr,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lo = if has_min != 0 {
        if min.is_null() {
            return ptr::null_mut();
        }
        Some(unsafe { (*min).clone() })
    } else {
        None
    };
    let hi = if has_max != 0 {
        if max.is_null() {
            return ptr::null_mut();
        }
        Some(unsafe { (*max).clone() })
    } else {
        None
    };
    let out = match (lo, hi) {
        (Some(l), Some(h)) => ee.clip(l, h),
        (Some(l), None) => ee.clip_min(l),
        (None, Some(h)) => ee.clip_max(h),
        (None, None) => ee,
    };
    Box::into_raw(Box::new(out))
}
