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

macro_rules! series_ref {
    ($name:ident -> $opt:ident, $s:ident => $values:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(s_ptr: *mut Series, index: usize) -> $opt {
            match series_at(s_ptr, index).map(|$s| $values) {
                Some(Ok(ca)) => $opt::from_option(ca.get(index)),
                _ => $opt::NONE,
            }
        }
    };
}

series_ref!(series_ref_i8 -> CompatOptI8, s => s.i8());
series_ref!(series_ref_i16 -> CompatOptI16, s => s.i16());
series_ref!(series_ref_i32 -> CompatOptI32, s => s.i32());
series_ref!(series_ref_i64 -> CompatOptI64, s => s.i64());
series_ref!(series_ref_u8 -> CompatOptU8, s => s.u8());
series_ref!(series_ref_u16 -> CompatOptU16, s => s.u16());
series_ref!(series_ref_u32 -> CompatOptU32, s => s.u32());
series_ref!(series_ref_u64 -> CompatOptU64, s => s.u64());
series_ref!(series_ref_f32 -> CompatOptF32, s => s.f32());
series_ref!(series_ref_f64 -> CompatOptF64, s => s.f64());
series_ref!(series_ref_bool -> CompatOptBool, s => s.bool());
series_ref!(
    series_ref_duration -> CompatOptI64,
    s => s.duration().map(|ca| ca.physical())
);
series_ref!(
    series_ref_time -> CompatOptI64,
    s => s.time().map(|ca| ca.physical())
);

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
