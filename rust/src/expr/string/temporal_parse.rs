use crate::prelude::*;
use crate::*;

pub(crate) fn strptime_options(
    format: Option<&str>,
    strict: u8,
    exact: u8,
    cache: u8,
) -> StrptimeOptions {
    StrptimeOptions {
        format: format.map(Into::into),
        strict: strict != 0,
        exact: exact != 0,
        cache: cache != 0,
    }
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
pub extern "C" fn expr_str_to_date_v2(
    e: *const Expr,
    format: StrArg,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    boxed_unguarded(|| {
        let e = unsafe { deref_arg(e, "the expression") }?;
        let format = unsafe { str_arg(format) }?;
        let options = strptime_options(format, strict, exact, cache);
        Ok(e.clone().str().to_date(options))
    })
}

#[no_mangle]
pub extern "C" fn expr_str_to_datetime_v2(
    e: *const Expr,
    format: StrArg,
    time_unit: i32,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    boxed_unguarded(|| {
        let e = unsafe { deref_arg(e, "the expression") }?;
        let format = unsafe { str_arg(format) }?;
        let unit = compat_time_unit_from_code(time_unit).ok_or_else(
            || polars_err!(ComputeError: "unknown time unit {}", time_unit),
        )?;
        let options = strptime_options(format, strict, exact, cache);
        Ok(e.clone()
            .str()
            .to_datetime(Some(unit), None, options, lit("raise")))
    })
}

/// `expr_str_to_datetime_v2` into a zone: a value with an offset converts
/// to it, a naive one is read as its wall clock, resolved by `ambiguous`.
#[no_mangle]
pub extern "C" fn expr_str_to_datetime_tz_v2(
    e: *const Expr,
    format: StrArg,
    time_unit: i32,
    tz: *const c_char,
    ambiguous: *const c_char,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    clear_last_error();
    let Some(e) = (unsafe { e.as_ref() }) else {
        set_last_error("expression is null");
        return ptr::null_mut();
    };
    let Some(format) = record(unsafe { str_arg(format) }) else {
        return ptr::null_mut();
    };
    let Some(DataType::Datetime(unit, tz)) = datetime_tz_dtype(time_unit, tz)
    else {
        return ptr::null_mut();
    };
    let Some(ambiguous) = ambiguous_name(ambiguous) else {
        return ptr::null_mut();
    };
    let options = strptime_options(format, strict, exact, cache);
    Box::into_raw(Box::new(e.clone().str().to_datetime(
        Some(unit),
        tz,
        options,
        lit(ambiguous),
    )))
}

#[no_mangle]
pub extern "C" fn expr_str_to_time_v2(
    e: *const Expr,
    format: StrArg,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    boxed_unguarded(|| {
        let e = unsafe { deref_arg(e, "the expression") }?;
        let format = unsafe { str_arg(format) }?;
        let options = strptime_options(format, strict, exact, cache);
        Ok(e.clone().str().to_time(options))
    })
}
