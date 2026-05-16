use crate::prelude::*;
use crate::*;

pub extern "C" fn dataframe_select(
    df_ptr: *mut DataFrame,
    name_ptrs: *const *const c_char,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(name_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    match df.select(&names) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_drop_columns(
    df_ptr: *mut DataFrame,
    name_ptrs: *const *const c_char,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(name_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    let mut out = df.clone();
    for name in &names {
        match out.drop_in_place(name) {
            Ok(_) => {}
            Err(_) => return ptr::null_mut(),
        }
    }
    Box::into_raw(Box::new(out))
}

#[no_mangle]
pub extern "C" fn dataframe_rename(
    df_ptr: *mut DataFrame,
    old: *const c_char,
    new: *const c_char,
) -> *mut DataFrame {
    if df_ptr.is_null() || old.is_null() || new.is_null() {
        return ptr::null_mut();
    }
    let old_str = match unsafe { CStr::from_ptr(old).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let new_str = match unsafe { CStr::from_ptr(new).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    let mut out = df.clone();
    match out.rename(old_str, new_str) {
        Ok(_) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_with_column(
    df_ptr: *mut DataFrame,
    series_ptr: *const Series,
) -> *mut DataFrame {
    if df_ptr.is_null() || series_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let s = unsafe { &*series_ptr };
    let mut out = df.clone();
    match out.with_column(s.clone()) {
        Ok(_) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_column_name(
    df_ptr: *mut DataFrame,
    index: usize,
) -> *const c_char {
    if df_ptr.is_null() {
        return ptr::null();
    }
    let df = unsafe { &*df_ptr };
    let names = df.get_column_names();
    match names.get(index) {
        Some(name) => rust_string_to_ptr(*name),
        None => ptr::null(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_column(
    df_ptr: *mut DataFrame,
    name: *const c_char,
) -> *mut Series {
    if df_ptr.is_null() || name.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let name_str = match unsafe { CStr::from_ptr(name).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match df.column(name_str) {
        Ok(s) => Box::into_raw(Box::new(s.clone())),
        Err(_) => ptr::null_mut(),
    }
}
