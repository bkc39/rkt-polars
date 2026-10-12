use crate::prelude::*;
use crate::{
    clear_last_error, datetime_tz_dtype, polars_dtype_from_compat,
    rust_string_to_ptr, CompatDType,
};
use std::sync::atomic::{AtomicUsize, Ordering};

static DROPPED: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn expr_drop_count() -> usize {
    DROPPED.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn expr_drop(e: *mut Expr) {
    if !e.is_null() {
        unsafe { drop(Box::from_raw(e)) };
        DROPPED.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn expr_to_string(e: *const Expr) -> *const c_char {
    if e.is_null() {
        return ptr::null();
    }
    rust_string_to_ptr(format!("{}", unsafe { &*e }))
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

const NS_IN_DAY: i64 = 86_400_000_000_000;

/// A Date, naive Datetime, Duration or Time literal from its physical value
/// (days, or the dtype's unit since the epoch or midnight). NULL for any
/// other dtype, or a value outside the dtype's range.
#[no_mangle]
pub extern "C" fn expr_lit_temporal(
    value: i64,
    dtype: CompatDType,
) -> *mut Expr {
    let scalar = match polars_dtype_from_compat(&dtype) {
        Some(DataType::Date) => match i32::try_from(value) {
            Ok(days) => Scalar::new_date(days),
            Err(_) => return ptr::null_mut(),
        },
        Some(DataType::Datetime(unit, None)) => {
            Scalar::new_datetime(value, unit, None)
        }
        Some(DataType::Duration(unit)) => Scalar::new_duration(value, unit),
        Some(DataType::Time) if (0..NS_IN_DAY).contains(&value) => {
            Scalar::new_time(value)
        }
        _ => return ptr::null_mut(),
    };
    Box::into_raw(Box::new(lit(scalar)))
}

/// A zoned Datetime literal from its unit's count since the epoch, UTC.
#[no_mangle]
pub extern "C" fn expr_lit_datetime_tz(
    value: i64,
    unit: i32,
    tz: *const c_char,
) -> *mut Expr {
    clear_last_error();
    match datetime_tz_dtype(unit, tz) {
        Some(DataType::Datetime(unit, tz)) => {
            Box::into_raw(Box::new(lit(Scalar::new_datetime(value, unit, tz))))
        }
        _ => ptr::null_mut(),
    }
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
