use super::test_util::{recorded_error, str_block, take_str};
use super::*;
use std::ptr;

#[test]
fn test_series_name_non_null() {
    let series = series_make();
    assert_eq!(take_str(series_name_v2(series)), "example");

    series_drop(series);
}

#[test]
fn test_series_name_null() {
    let name_ptr = series_name_v2(ptr::null_mut());
    assert!(name_ptr.is_null());
}

#[test]
fn free_non_null_series() {
    let series = series_make();
    assert!(!series.is_null());
    series_drop(series);
}

#[test]
fn free_empty_series() {
    let series = series_empty();
    assert!(!series.is_null());
    series_drop(series);
}

#[test]
fn free_null_series() {
    let series: *mut Series = ptr::null_mut();
    series_drop(series);
}

#[test]
fn test_empty_series_name() {
    let series = series_empty();
    assert_eq!(take_str(series_name_v2(series)), "");

    series_drop(series);
}

#[test]
fn test_rename_series_non_null() {
    let series = series_make();
    let name = str_block("new_name");
    assert_eq!(series_rename_v2(series, name.as_ptr()), 0);
    assert_eq!(take_str(series_name_v2(series)), "new_name");
    series_drop(series);
}

#[test]
fn test_rename_series_with_empty_string() {
    let series = series_make();
    let name = str_block("");
    assert_eq!(series_rename_v2(series, name.as_ptr()), 0);
    assert_eq!(take_str(series_name_v2(series)), "");
    series_drop(series);
}

#[test]
fn test_rename_series_null_series_pointer() {
    let name = str_block("new_name");
    assert_eq!(series_rename_v2(ptr::null_mut(), name.as_ptr()), -1);
    assert_eq!(recorded_error().as_deref(), Some("series is null"));
}

#[test]
fn test_rename_series_null_new_name_pointer() {
    let series = series_make();
    assert_eq!(series_rename_v2(series, ptr::null()), -1);
    assert_eq!(recorded_error().as_deref(), Some("the name is null"));
    assert_eq!(take_str(series_name_v2(series)), "example");
    series_drop(series);
}

#[test]
fn test_series_dtype_non_null() {
    let series = series_make();
    let dtype = series_dtype(series);
    assert_eq!(dtype.tag, CompatDTypeTag::Int32 as i32);
    assert_eq!(dtype.time_unit, CompatTimeUnit::None as i32);
    assert_eq!(dtype.flags, 0);
    assert_eq!(dtype.array_width, 0);

    series_drop(series);
}

#[test]
fn test_series_dtype_null() {
    let dtype = series_dtype(ptr::null_mut());
    assert_eq!(dtype.tag, CompatDTypeTag::Unknown as i32);
    assert_eq!(dtype.time_unit, CompatTimeUnit::None as i32);
}

#[test]
fn test_series_len_non_null() {
    let series = series_make();
    let len = series_len(series);
    assert_eq!(len, 4);
    series_drop(series);
}

#[test]
fn test_series_len_null() {
    let len = series_len(ptr::null_mut());
    assert_eq!(len, 0);
}

#[test]
fn test_series_len_empty_series() {
    let series = series_empty();
    let len = series_len(series);
    assert_eq!(len, 0);
    series_drop(series);
}

#[test]
fn test_series_null_count_non_null() {
    let series = series_make();
    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);
    series_drop(series);
}

#[test]
fn test_series_null_count_null() {
    let null_count = series_null_count(ptr::null_mut());
    assert_eq!(null_count, 0);
}

#[test]
fn test_series_null_count_empty_series() {
    let series = series_empty();
    let null_count = series_null_count(series);
    assert_eq!(null_count, 0);
    series_drop(series);
}
