use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn series_ref_is_null(s_ptr: *mut Series, index: usize) -> i32 {
    if s_ptr.is_null() {
        return -1;
    }
    let s = unsafe { &*s_ptr };
    if index >= s.len() {
        return -1;
    }
    if s.null_count() == 0 {
        return 0;
    }
    if s.is_null().get(index).unwrap_or(false) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI32 {
    if s_ptr.is_null() {
        return CompatOptI32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => CompatOptI32::from_option(ca.get(index)),
        Err(_) => CompatOptI32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i8(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI8 {
    if s_ptr.is_null() {
        return CompatOptI8::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i8() {
        Ok(ca) => CompatOptI8::from_option(ca.get(index)),
        Err(_) => CompatOptI8::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i16(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI16 {
    if s_ptr.is_null() {
        return CompatOptI16::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i16() {
        Ok(ca) => CompatOptI16::from_option(ca.get(index)),
        Err(_) => CompatOptI16::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i64(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    if s_ptr.is_null() {
        return CompatOptI64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i64() {
        Ok(ca) => CompatOptI64::from_option(ca.get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u8(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU8 {
    if s_ptr.is_null() {
        return CompatOptU8::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u8() {
        Ok(ca) => CompatOptU8::from_option(ca.get(index)),
        Err(_) => CompatOptU8::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u16(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU16 {
    if s_ptr.is_null() {
        return CompatOptU16::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u16() {
        Ok(ca) => CompatOptU16::from_option(ca.get(index)),
        Err(_) => CompatOptU16::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU32 {
    if s_ptr.is_null() {
        return CompatOptU32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u32() {
        Ok(ca) => CompatOptU32::from_option(ca.get(index)),
        Err(_) => CompatOptU32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u64(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU64 {
    if s_ptr.is_null() {
        return CompatOptU64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u64() {
        Ok(ca) => CompatOptU64::from_option(ca.get(index)),
        Err(_) => CompatOptU64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_f32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptF32 {
    if s_ptr.is_null() {
        return CompatOptF32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f32() {
        Ok(ca) => CompatOptF32::from_option(ca.get(index)),
        Err(_) => CompatOptF32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_f64(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f64() {
        Ok(ca) => CompatOptF64::from_option(ca.get(index)),
        Err(_) => CompatOptF64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_bool(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptBool {
    if s_ptr.is_null() {
        return CompatOptBool::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.bool() {
        Ok(ca) => CompatOptBool::from_option(ca.get(index)),
        Err(_) => CompatOptBool::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_str(
    s_ptr: *mut Series,
    index: usize,
) -> *const c_char {
    if s_ptr.is_null() {
        return ptr::null();
    }
    let s = unsafe { &*s_ptr };
    match s.str() {
        Ok(ca) => ca.get(index).map(rust_string_to_ptr).unwrap_or(ptr::null()),
        Err(_) => ptr::null(),
    }
}

pub(crate) fn date_days_to_ymd(days: i32) -> Option<YMD> {
    NaiveDate::from_ymd_opt(1970, 1, 1)
        .and_then(|epoch| {
            epoch.checked_add_signed(ChronoDuration::days(days as i64))
        })
        .map(|date| YMD {
            year: date.year(),
            month: date.month(),
            day: date.day(),
        })
}

#[no_mangle]
pub extern "C" fn series_ref_date(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptYMD {
    if s_ptr.is_null() {
        return CompatOptYMD::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.date() {
        Ok(ca) => ca
            .get(index)
            .and_then(date_days_to_ymd)
            .map(CompatOptYMD::some)
            .unwrap_or(CompatOptYMD::NONE),
        Err(_) => CompatOptYMD::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_duration(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    if s_ptr.is_null() {
        return CompatOptI64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.duration() {
        Ok(ca) => CompatOptI64::from_option(ca.get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_time(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    if s_ptr.is_null() {
        return CompatOptI64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.time() {
        Ok(ca) => CompatOptI64::from_option(ca.get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

pub(crate) fn datetime_value_to_ymdhms(
    value: i64,
    time_unit: &TimeUnit,
) -> Option<YMDHMS> {
    let (secs, nanos) = match time_unit {
        TimeUnit::Nanoseconds => (
            value.div_euclid(1_000_000_000),
            value.rem_euclid(1_000_000_000) as u32,
        ),
        TimeUnit::Microseconds => (
            value.div_euclid(1_000_000),
            (value.rem_euclid(1_000_000) * 1_000) as u32,
        ),
        TimeUnit::Milliseconds => (
            value.div_euclid(1_000),
            (value.rem_euclid(1_000) * 1_000_000) as u32,
        ),
    };
    DateTime::from_timestamp(secs, nanos)
        .map(|dt| dt.naive_utc())
        .map(|dt| YMDHMS {
            year: dt.year(),
            month: dt.month(),
            day: dt.day(),
            hour: dt.hour(),
            minute: dt.minute(),
            second: dt.second(),
        })
}

#[no_mangle]
pub extern "C" fn series_ref_ymdhms(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptYMDHMS {
    if s_ptr.is_null() {
        return CompatOptYMDHMS::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.datetime() {
        Ok(ca) => ca
            .get(index)
            .and_then(|value| datetime_value_to_ymdhms(value, &ca.time_unit()))
            .map(CompatOptYMDHMS::some)
            .unwrap_or(CompatOptYMDHMS::NONE),
        Err(_) => CompatOptYMDHMS::NONE,
    }
}
