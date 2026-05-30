use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn series_new_ymdhms(
    name: *const c_char,
    data: *const YMDHMS,
    length: usize,
) -> *mut Series {
    if data.is_null() {
        std::ptr::null_mut()
    } else {
        let ymdhms_slice = unsafe { std::slice::from_raw_parts(data, length) };
        let naive_dates: Vec<NaiveDateTime> = ymdhms_slice
            .iter()
            .map(|ymdhms| {
                NaiveDate::from_ymd_opt(ymdhms.year, ymdhms.month, ymdhms.day)
                    .unwrap()
                    .and_hms_opt(ymdhms.hour, ymdhms.minute, ymdhms.second)
                    .unwrap()
            })
            .collect();
        Box::into_raw(Box::new(Series::new(name_from_ptr(name), naive_dates)))
    }
}

pub(crate) fn ymdhms_to_naive_datetime(
    ymdhms: &YMDHMS,
) -> Option<NaiveDateTime> {
    NaiveDate::from_ymd_opt(ymdhms.year, ymdhms.month, ymdhms.day).and_then(
        |date| date.and_hms_opt(ymdhms.hour, ymdhms.minute, ymdhms.second),
    )
}

#[no_mangle]
pub extern "C" fn series_new_opt_ymdhms(
    name: *const c_char,
    data: *const YMDHMS,
    valid: *const u8,
    length: usize,
) -> *mut Series {
    let Some((values, valid)) = valid_slices(data, valid, length) else {
        return ptr::null_mut();
    };
    let naive_dates =
        values.iter().zip(valid.iter()).map(|(ymdhms, is_valid)| {
            if *is_valid == 0 {
                None
            } else {
                ymdhms_to_naive_datetime(ymdhms)
            }
        });
    let ca = DatetimeChunked::from_naive_datetime_options(
        name_from_ptr(name),
        naive_dates,
        TimeUnit::Milliseconds,
    );
    Box::into_raw(Box::new(ca.into_series()))
}
