use crate::prelude::*;

#[no_mangle]
pub extern "C" fn dataframe_hstack(
    df_ptr: *mut DataFrame,
    series_ptrs: *const *const Series,
    length: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() || (series_ptrs.is_null() && length != 0) {
        return ptr::null_mut();
    }
    let columns: Vec<Series> = if length == 0 {
        Vec::new()
    } else {
        let slice = unsafe { std::slice::from_raw_parts(series_ptrs, length) };
        if slice.iter().any(|p| p.is_null()) {
            return ptr::null_mut();
        }
        slice.iter().map(|&p| unsafe { (*p).clone() }).collect()
    };
    let df = unsafe { &*df_ptr };
    match df.hstack(&columns) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_vstack(
    a_ptr: *mut DataFrame,
    b_ptr: *mut DataFrame,
) -> *mut DataFrame {
    if a_ptr.is_null() || b_ptr.is_null() {
        return ptr::null_mut();
    }
    let a = unsafe { &*a_ptr };
    let b = unsafe { &*b_ptr };
    match a.vstack(b) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}
