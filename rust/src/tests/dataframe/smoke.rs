use super::*;
use std::ptr;

#[test]
fn free_non_null_dataframe() {
    let df = dataframe_make();
    assert!(!df.is_null());
    dataframe_drop(df);
}

#[test]
fn free_empty_dataframe() {
    let df = dataframe_empty();
    assert!(!df.is_null());
    dataframe_drop(df);
}

#[test]
fn free_null_dataframe() {
    let df: *mut DataFrame = ptr::null_mut();
    dataframe_drop(df);
}

#[test]
fn get_shape_of_non_null_dataframe() {
    let df = dataframe_make();
    let shape = dataframe_shape(df);
    assert_eq!(shape.rows, 0);
    assert_eq!(shape.cols, 0);
    dataframe_drop(df);
}

#[test]
fn get_shape_of_empty_dataframe() {
    let df = dataframe_empty();
    let shape = dataframe_shape(df);
    assert_eq!(shape.rows, 0);
    assert_eq!(shape.cols, 0);
    dataframe_drop(df);
}

#[test]
fn get_shape_of_null_dataframe() {
    let df: *mut DataFrame = ptr::null_mut();
    let shape = dataframe_shape(df);
    assert_eq!(shape.rows, 0);
    assert_eq!(shape.cols, 0);
}
