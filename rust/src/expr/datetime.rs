use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn expr_dt_year(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().year()))
}

#[no_mangle]
pub extern "C" fn expr_dt_month(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().month()))
}

#[no_mangle]
pub extern "C" fn expr_dt_day(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().day()))
}

#[no_mangle]
pub extern "C" fn expr_dt_hour(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().hour()))
}

#[no_mangle]
pub extern "C" fn expr_dt_minute(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().minute()))
}

#[no_mangle]
pub extern "C" fn expr_dt_second(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().second()))
}

#[no_mangle]
pub extern "C" fn expr_dt_iso_year(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().iso_year()))
}

#[no_mangle]
pub extern "C" fn expr_dt_quarter(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().quarter()))
}

#[no_mangle]
pub extern "C" fn expr_dt_week(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().week()))
}

#[no_mangle]
pub extern "C" fn expr_dt_weekday(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().weekday()))
}

#[no_mangle]
pub extern "C" fn expr_dt_ordinal_day(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().ordinal_day()))
}

#[no_mangle]
pub extern "C" fn expr_dt_is_leap_year(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().is_leap_year()))
}

#[no_mangle]
pub extern "C" fn expr_dt_date(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().date()))
}

#[no_mangle]
pub extern "C" fn expr_dt_time(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().time()))
}

#[no_mangle]
pub extern "C" fn expr_dt_millisecond(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().millisecond()))
}

#[no_mangle]
pub extern "C" fn expr_dt_microsecond(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().microsecond()))
}

#[no_mangle]
pub extern "C" fn expr_dt_nanosecond(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().nanosecond()))
}

#[no_mangle]
pub extern "C" fn expr_dt_timestamp(e: *const Expr, unit: i32) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let tu = match unit {
        x if x == CompatTimeUnit::Nanoseconds as i32 => TimeUnit::Nanoseconds,
        x if x == CompatTimeUnit::Microseconds as i32 => TimeUnit::Microseconds,
        x if x == CompatTimeUnit::Milliseconds as i32 => TimeUnit::Milliseconds,
        _ => return ptr::null_mut(),
    };
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().timestamp(tu)))
}

#[no_mangle]
pub extern "C" fn expr_dt_strftime(
    e: *const Expr,
    format: *const c_char,
) -> *mut Expr {
    if e.is_null() || format.is_null() {
        return ptr::null_mut();
    }
    let fmt = match unsafe { CStr::from_ptr(format).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().strftime(fmt)))
}

#[no_mangle]
pub extern "C" fn expr_dt_truncate(
    e: *const Expr,
    every: *const Expr,
) -> *mut Expr {
    if e.is_null() || every.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let ev = unsafe { (*every).clone() };
    Box::into_raw(Box::new(ee.dt().truncate(ev)))
}
