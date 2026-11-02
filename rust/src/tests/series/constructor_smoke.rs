use super::test_util::take_str;
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

    assert_eq!(take_str(series_name_v2(series)), "i32_series");

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

    assert_eq!(take_str(series_name_v2(series)), "i32_series");

    series_drop(series);
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

    assert_eq!(take_str(series_name_v2(series)), "f64_series");

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

    assert_eq!(take_str(series_name_v2(series)), "ymdhms_series");

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

    assert_eq!(take_str(series_name_v2(series)), "ymdhms_series");

    series_drop(series);
}
