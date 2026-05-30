use super::*;
use std::ptr;

#[test]
fn test_series_new_i32_valid() {
    let data = [1, 2, 3, 4];
    let data_ptr = data.as_ptr();

    let name = CString::new("i32_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_i32(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 4);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "i32_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}

#[test]
fn test_series_new_i32_null_name() {
    let data = [1, 2, 3, 4];
    let data_ptr = data.as_ptr();

    let series = series_new_i32(ptr::null(), data_ptr, data.len());
    assert!(series.is_null());
}

#[test]
fn test_series_new_i32_null_data() {
    let name = CString::new("i32_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_i32(name_ptr, ptr::null(), 4);
    assert!(series.is_null());
}

#[test]
fn test_series_new_i32_empty_data() {
    let data: Vec<i32> = Vec::new();
    let data_ptr = data.as_ptr();

    let name = CString::new("i32_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_i32(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 0);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "i32_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}

#[test]
fn test_string_drop_non_null() {
    let s = CString::new("hello").unwrap();
    let s_ptr = s.into_raw();

    string_drop(s_ptr);
}

#[test]
fn test_string_drop_null() {
    string_drop(ptr::null_mut());
    // Should not do anything, hence no assertion or panic
}

#[test]
fn test_series_new_f64_valid() {
    let data = [1.1, 2.2, 3.3, 4.4];
    let data_ptr = data.as_ptr();

    let name = CString::new("f64_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_f64(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 4);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "f64_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}

#[test]
fn test_series_new_str_valid() {
    let data = [
        CString::new("one").unwrap(),
        CString::new("two").unwrap(),
        CString::new("three").unwrap(),
    ];
    let data_ptrs: Vec<*const c_char> =
        data.iter().map(|s| s.as_ptr()).collect();
    let data_ptr = data_ptrs.as_ptr();

    let name = CString::new("str_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_str(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 3);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "str_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}

#[test]
fn test_series_new_str_null_name() {
    let data = [
        CString::new("one").unwrap(),
        CString::new("two").unwrap(),
        CString::new("three").unwrap(),
    ];
    let data_ptrs: Vec<*const c_char> =
        data.iter().map(|s| s.as_ptr()).collect();
    let data_ptr = data_ptrs.as_ptr();

    let series = series_new_str(ptr::null(), data_ptr, data.len());
    assert!(!series.is_null());
}

#[test]
fn test_series_new_str_null_data() {
    let name = CString::new("str_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_str(name_ptr, ptr::null(), 3);
    assert!(series.is_null());
}

#[test]
fn test_series_new_str_empty_data() {
    let data: Vec<*const c_char> = Vec::new();
    let data_ptr = data.as_ptr();

    let name = CString::new("str_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_str(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 0);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "str_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}

#[test]
fn test_series_new_ymdhms_valid() {
    let data = [
        YMDHMS {
            year: 2021,
            month: 5,
            day: 20,
            hour: 10,
            minute: 30,
            second: 45,
        },
        YMDHMS {
            year: 2022,
            month: 6,
            day: 21,
            hour: 11,
            minute: 31,
            second: 46,
        },
    ];
    let data_ptr = data.as_ptr();

    let name = CString::new("ymdhms_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_ymdhms(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 2);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "ymdhms_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}

#[test]
fn test_series_new_ymdhms_null_name() {
    let data = [
        YMDHMS {
            year: 2021,
            month: 5,
            day: 20,
            hour: 10,
            minute: 30,
            second: 45,
        },
        YMDHMS {
            year: 2022,
            month: 6,
            day: 21,
            hour: 11,
            minute: 31,
            second: 46,
        },
    ];
    let data_ptr = data.as_ptr();

    let series = series_new_ymdhms(ptr::null(), data_ptr, data.len());
    assert!(!series.is_null());
}

#[test]
fn test_series_new_ymdhms_null_data() {
    let name = CString::new("ymdhms_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_ymdhms(name_ptr, ptr::null(), 2);
    assert!(series.is_null());
}

#[test]
fn test_series_new_ymdhms_empty_data() {
    let data: Vec<YMDHMS> = Vec::new();
    let data_ptr = data.as_ptr();

    let name = CString::new("ymdhms_series").unwrap();
    let name_ptr = name.as_ptr();

    let series = series_new_ymdhms(name_ptr, data_ptr, data.len());
    assert!(!series.is_null());

    let len = series_len(series);
    assert_eq!(len, 0);

    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);

    let name_ptr = series_name(series);
    let c_str = unsafe { CStr::from_ptr(name_ptr) };
    let series_name = c_str.to_str().unwrap();
    assert_eq!(series_name, "ymdhms_series");

    // Free the CString allocated by series_name
    unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

    series_drop(series);
}
