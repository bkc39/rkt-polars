use crate::prelude::*;
use crate::*;

pub(crate) fn strptime_options(
    format: Option<String>,
    strict: u8,
    exact: u8,
    cache: u8,
) -> StrptimeOptions {
    StrptimeOptions {
        format,
        strict: strict != 0,
        exact: exact != 0,
        cache: cache != 0,
    }
}

pub(crate) fn c_string_option(
    format: *const c_char,
    has_format: u8,
) -> Option<String> {
    if has_format == 0 || format.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(format).to_str().ok().map(String::from) }
}

pub(crate) fn compat_time_unit_from_code(unit: i32) -> Option<TimeUnit> {
    match unit {
        x if x == CompatTimeUnit::Nanoseconds as i32 => {
            Some(TimeUnit::Nanoseconds)
        }
        x if x == CompatTimeUnit::Microseconds as i32 => {
            Some(TimeUnit::Microseconds)
        }
        x if x == CompatTimeUnit::Milliseconds as i32 => {
            Some(TimeUnit::Milliseconds)
        }
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn expr_str_to_date(
    e: *const Expr,
    format: *const c_char,
    has_format: u8,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let options = strptime_options(
        c_string_option(format, has_format),
        strict,
        exact,
        cache,
    );
    Box::into_raw(Box::new(ee.str().to_date(options)))
}

#[no_mangle]
pub extern "C" fn expr_str_to_datetime(
    e: *const Expr,
    format: *const c_char,
    has_format: u8,
    time_unit: i32,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let Some(tu) = compat_time_unit_from_code(time_unit) else {
        return ptr::null_mut();
    };
    let ee = unsafe { (*e).clone() };
    let options = strptime_options(
        c_string_option(format, has_format),
        strict,
        exact,
        cache,
    );
    Box::into_raw(Box::new(ee.str().to_datetime(
        Some(tu),
        None,
        options,
        lit("raise"),
    )))
}

#[no_mangle]
pub extern "C" fn expr_str_to_time(
    e: *const Expr,
    format: *const c_char,
    has_format: u8,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let options = strptime_options(
        c_string_option(format, has_format),
        strict,
        exact,
        cache,
    );
    Box::into_raw(Box::new(ee.str().to_time(options)))
}
