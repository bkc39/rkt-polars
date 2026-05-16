use crate::prelude::*;

#[no_mangle]
pub extern "C" fn series_head(s_ptr: *mut Series, n: usize) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.head(Some(n))))
}

#[no_mangle]
pub extern "C" fn series_tail(s_ptr: *mut Series, n: usize) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.tail(Some(n))))
}

#[no_mangle]
pub extern "C" fn series_slice(
    s_ptr: *mut Series,
    offset: i64,
    length: usize,
) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.slice(offset, length)))
}

#[no_mangle]
pub extern "C" fn series_reverse(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.reverse()))
}

#[no_mangle]
pub extern "C" fn series_drop_nulls(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.drop_nulls()))
}

#[no_mangle]
pub extern "C" fn series_unique(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    match s.unique() {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_sort(
    s_ptr: *mut Series,
    descending: u8,
) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    let opts = SortOptions::default().with_order_descending(descending != 0);
    match s.sort_with(opts) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}
