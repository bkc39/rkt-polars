use crate::prelude::*;
use crate::{
    boxed_unguarded, clear_last_error, datetime_tz_dtype, deref_arg,
    guard_panic, name_arg, polars_dtype_from_compat, str_out, CompatDType,
    StrArg, StrOut,
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
pub extern "C" fn expr_to_string_v2(e: *const Expr) -> StrOut {
    clear_last_error();
    if e.is_null() {
        return ptr::null_mut();
    }
    let e = unsafe { &*e };
    guard_panic(|| Some(format!("{}", e)))
        .map_or(ptr::null_mut(), |text| str_out(&text))
}

#[no_mangle]
pub extern "C" fn expr_col_v2(name: StrArg) -> *mut Expr {
    boxed_unguarded(|| Ok(col(unsafe { name_arg(name, "the column name") }?)))
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
pub extern "C" fn expr_lit_u64(v: u64) -> *mut Expr {
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
pub extern "C" fn expr_lit_str_v2(value: StrArg) -> *mut Expr {
    boxed_unguarded(|| Ok(lit(unsafe { name_arg(value, "the string") }?)))
}

/// Python's `pl.lit(None)`: a null literal of dtype Null.
#[no_mangle]
pub extern "C" fn expr_lit_null() -> *mut Expr {
    Box::into_raw(Box::new(lit(Null {})))
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
pub extern "C" fn expr_alias_v2(e: *const Expr, name: StrArg) -> *mut Expr {
    boxed_unguarded(|| {
        let e = unsafe { deref_arg(e, "expression") }?;
        Ok(e.clone().alias(unsafe { name_arg(name, "the name") }?))
    })
}

expr_unop!(expr_name_keep, |e| e.name().keep());

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
