use crate::prelude::*;
use crate::*;

pub(crate) fn name_from_ptr(p: *const c_char) -> &'static str {
    if p.is_null() {
        return "";
    }
    unsafe { CStr::from_ptr(p).to_str() }.unwrap_or_default()
}

#[no_mangle]
pub extern "C" fn series_new_str(
    name: *const c_char,
    data: *const *const c_char,
    length: usize,
) -> *mut Series {
    if data.is_null() {
        return std::ptr::null_mut();
    }

    let slice: &[*const c_char] =
        unsafe { std::slice::from_raw_parts(data, length) };
    let vec: Vec<&str> = slice
        .iter()
        .map(|&ptr| unsafe { CStr::from_ptr(ptr).to_str().unwrap_or_default() })
        .collect();
    Box::into_raw(Box::new(Series::new(name_from_ptr(name), vec)))
}

#[no_mangle]
pub extern "C" fn series_new_opt_str(
    name: *const c_char,
    data: *const *const c_char,
    valid: *const u8,
    length: usize,
) -> *mut Series {
    if data.is_null() && length != 0 {
        return std::ptr::null_mut();
    }
    let Some((values, valid)) = valid_slices(data, valid, length) else {
        return ptr::null_mut();
    };
    let strings: Vec<Option<&str>> = values
        .iter()
        .zip(valid.iter())
        .map(|(value, is_valid)| {
            if *is_valid == 0 || value.is_null() {
                None
            } else {
                unsafe { CStr::from_ptr(*value).to_str().ok() }
            }
        })
        .collect();
    Box::into_raw(Box::new(Series::new(name_from_ptr(name), strings)))
}
