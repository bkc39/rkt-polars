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
    match s.get(index) {
        Ok(AnyValue::Null) => 1,
        Ok(_) => 0,
        Err(_) => -1,
    }
}

fn series_at<'a>(s_ptr: *mut Series, index: usize) -> Option<&'a Series> {
    let s = unsafe { s_ptr.as_ref() }?;
    (index < s.len()).then_some(s)
}

#[no_mangle]
pub extern "C" fn series_ref_i32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI32 {
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptI32::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptI8::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptI16::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptI64::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptU8::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptU16::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptU32::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptU64::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptF32::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptF64::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptBool::NONE;
    };
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
    let Some(s) = series_at(s_ptr, index) else {
        return ptr::null();
    };
    if s.dtype().is_categorical() || s.dtype().is_enum() {
        return match s.get(index) {
            Ok(value) => {
                value.get_str().map_or(ptr::null(), rust_string_to_ptr)
            }
            Err(_) => ptr::null(),
        };
    }
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptYMD::NONE;
    };
    match s.date() {
        Ok(ca) => ca
            .physical()
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
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptI64::NONE;
    };
    match s.duration() {
        Ok(ca) => CompatOptI64::from_option(ca.physical().get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_time(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    let Some(s) = series_at(s_ptr, index) else {
        return CompatOptI64::NONE;
    };
    match s.time() {
        Ok(ca) => CompatOptI64::from_option(ca.physical().get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}
