use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn series_new_bool(
    name: *const c_char,
    data: *const u8,
    length: usize,
) -> *mut Series {
    if name.is_null() || (data.is_null() && length != 0) {
        return ptr::null_mut();
    }
    let bools: Vec<bool> = if length == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(data, length) }
            .iter()
            .map(|&b| b != 0)
            .collect()
    };
    let n = name_from_ptr(name);
    Box::into_raw(Box::new(Series::new(n, bools)))
}

#[no_mangle]
pub extern "C" fn series_new_opt_bool(
    name: *const c_char,
    data: *const u8,
    valid: *const u8,
    length: usize,
) -> *mut Series {
    if name.is_null() {
        return ptr::null_mut();
    }
    let Some((values, valid)) = valid_slices(data, valid, length) else {
        return ptr::null_mut();
    };
    let bools: Vec<Option<bool>> = values
        .iter()
        .zip(valid.iter())
        .map(|(value, is_valid)| {
            if *is_valid == 0 {
                None
            } else {
                Some(*value != 0)
            }
        })
        .collect();
    Box::into_raw(Box::new(Series::new(name_from_ptr(name), bools)))
}
