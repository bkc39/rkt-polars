use crate::prelude::*;
use crate::*;

/// The zone a caller names, in polars' canonical spelling (`+01:00` is
/// `Etc/GMT-1`) and known to chrono-tz's database; `None` records why not.
pub(crate) fn named_time_zone(name: *const c_char) -> Option<TimeZone> {
    if name.is_null() {
        set_last_error("time zone is null");
        return None;
    }
    let name = record(
        unsafe { CStr::from_ptr(name) }
            .to_str()
            .map_err(|err| format!("time zone is not valid UTF-8: {err}")),
    )?;
    match record(TimeZone::opt_try_new(Some(name)))? {
        // opt_try_new accepts any name when POLARS_IGNORE_TIMEZONE_PARSE_ERROR
        // is set; validate_time_zone does not read it.
        Some(tz) if tz.as_str() != "*" => {
            record(TimeZone::validate_time_zone(tz.as_str()))?;
            Some(tz)
        }
        _ => {
            set_last_error(format!("not a time zone: '{name}'"));
            None
        }
    }
}

pub(crate) fn datetime_tz_dtype(
    unit: i32,
    name: *const c_char,
) -> Option<DataType> {
    let unit =
        record(compat_time_unit_from_code(unit).ok_or("unknown time unit"))?;
    Some(DataType::Datetime(unit, Some(named_time_zone(name)?)))
}

fn c_str<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(p) }.to_str().ok()
    }
}

/// A resolution's name as a failure reason shows it.
fn shown(name: Option<&str>) -> String {
    name.map_or_else(|| "(null or not UTF-8)".to_string(), |s| format!("'{s}'"))
}

/// How a wall-clock time that names two instants resolves.
pub(crate) fn ambiguous_name(name: *const c_char) -> Option<&'static str> {
    match c_str(name) {
        Some("raise") => Some("raise"),
        Some("earliest") => Some("earliest"),
        Some("latest") => Some("latest"),
        Some("null") => Some("null"),
        other => {
            set_last_error(format!(
                "invalid ambiguous {}, expected one of 'earliest', 'latest', \
                 'null' or 'raise'",
                shown(other)
            ));
            None
        }
    }
}

/// How a wall-clock time that names no instant resolves.
pub(crate) fn non_existent(name: *const c_char) -> Option<NonExistent> {
    match c_str(name) {
        Some("raise") => Some(NonExistent::Raise),
        Some("null") => Some(NonExistent::Null),
        other => {
            set_last_error(format!(
                "invalid non-existent {}, expected 'null' or 'raise'",
                shown(other)
            ));
            None
        }
    }
}

/// `dt.replace_time_zone`'s two resolution arguments.
pub(crate) fn tz_resolution(
    ambiguous: *const c_char,
    non_existent_name: *const c_char,
) -> Option<(&'static str, NonExistent)> {
    Some((ambiguous_name(ambiguous)?, non_existent(non_existent_name)?))
}

/// A NULL name is no zone; any other must name one.
pub(crate) fn optional_time_zone(
    name: *const c_char,
) -> Option<Option<TimeZone>> {
    if name.is_null() {
        Some(None)
    } else {
        named_time_zone(name).map(Some)
    }
}

fn series_ref<'a>(s_ptr: *const Series) -> Option<&'a Series> {
    let s = unsafe { s_ptr.as_ref() };
    if s.is_none() {
        set_last_error("series is null");
    }
    s
}

fn datetime_of(s: &Series) -> Option<DatetimeChunked> {
    match s.dtype() {
        DataType::Datetime(..) => record(s.datetime()).cloned(),
        dtype => {
            set_last_error(format!("expected Datetime, got {dtype}"));
            None
        }
    }
}

fn boxed(s: Option<Series>) -> *mut Series {
    s.map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

/// The zone of a zoned Datetime series; NULL for any other dtype.
#[no_mangle]
pub extern "C" fn series_time_zone(s_ptr: *const Series) -> *const c_char {
    match unsafe { s_ptr.as_ref() }.map(|s| s.dtype()) {
        Some(DataType::Datetime(_, Some(tz))) => {
            rust_string_to_ptr(tz.as_str())
        }
        _ => ptr::null(),
    }
}

/// `series_cast` to a zoned Datetime: a naive datetime or an integer is read
/// as UTC, a zoned one keeps its instant.
#[no_mangle]
pub extern "C" fn series_cast_datetime_tz(
    s_ptr: *const Series,
    unit: i32,
    tz: *const c_char,
) -> *mut Series {
    clear_last_error();
    let Some(s) = series_ref(s_ptr) else {
        return ptr::null_mut();
    };
    boxed(
        datetime_tz_dtype(unit, tz)
            .and_then(|dtype| guard_panic(|| record(s.cast(&dtype)))),
    )
}

/// The same instants in another zone (`dt.convert_time_zone`).
#[no_mangle]
pub extern "C" fn series_dt_convert_time_zone(
    s_ptr: *const Series,
    tz: *const c_char,
) -> *mut Series {
    clear_last_error();
    let Some(s) = series_ref(s_ptr) else {
        return ptr::null_mut();
    };
    boxed(named_time_zone(tz).and_then(|tz| {
        guard_panic(|| {
            let mut ca = datetime_of(s)?;
            record(ca.set_time_zone(tz))?;
            Some(ca.into_series())
        })
    }))
}

/// The same wall clock in another zone, or none for a NULL `tz`
/// (`dt.replace_time_zone`).
#[no_mangle]
pub extern "C" fn series_dt_replace_time_zone(
    s_ptr: *const Series,
    tz: *const c_char,
    ambiguous: *const c_char,
    non_existent: *const c_char,
) -> *mut Series {
    clear_last_error();
    let Some(s) = series_ref(s_ptr) else {
        return ptr::null_mut();
    };
    let Some(tz) = optional_time_zone(tz) else {
        return ptr::null_mut();
    };
    let Some((ambiguous, non_existent)) =
        tz_resolution(ambiguous, non_existent)
    else {
        return ptr::null_mut();
    };
    boxed(guard_panic(|| {
        let ca = datetime_of(s)?;
        let ambiguous =
            StringChunked::from_slice(PlSmallStr::EMPTY, &[ambiguous]);
        record(replace_time_zone(
            &ca,
            tz.as_ref(),
            &ambiguous,
            non_existent,
        ))
        .map(|out| out.into_series())
    }))
}
