use polars::prelude::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

/// A struct to represent a tuple (usize, usize) for C FFI
#[repr(C)]
pub struct Shape {
    pub rows: usize,
    pub cols: usize,
}

#[no_mangle]
pub extern "C" fn string_drop(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

#[no_mangle]
pub extern "C" fn dataframe_make() -> *mut DataFrame {
    let df = DataFrame::default();
    let boxed_df = Box::new(df);
    Box::into_raw(boxed_df)
}

#[no_mangle]
pub extern "C" fn dataframe_empty() -> *mut DataFrame {
    Box::into_raw(Box::new(DataFrame::empty()))
}

#[no_mangle]
pub extern "C" fn dataframe_drop(df_ptr: *mut DataFrame) {
    if !df_ptr.is_null() {
        unsafe { drop(Box::from_raw(df_ptr)) };
    }
}

#[no_mangle]
pub extern "C" fn dataframe_shape(df_ptr: *mut DataFrame) -> Shape {
    if df_ptr.is_null() {
        Shape { rows: 0, cols: 0 }
    } else {
        let df = unsafe { &*df_ptr };
        let shape = df.shape();
        Shape {
            rows: shape.0,
            cols: shape.1,
        }
    }
}

#[no_mangle]
pub extern "C" fn series_make() -> *mut Series {
    let s = Series::new("example", &[1, 2, 3, 4]);
    let boxed_s = Box::new(s);
    Box::into_raw(boxed_s)
}

#[no_mangle]
pub extern "C" fn series_empty() -> *mut Series {
    Box::into_raw(Box::new(Series::new_empty("", &DataType::Int32)))
}

#[no_mangle]
pub extern "C" fn series_drop(s_ptr: *mut Series) {
    if !s_ptr.is_null() {
        unsafe { drop(Box::from_raw(s_ptr)) };
    }
}

#[no_mangle]
pub extern "C" fn series_name(s_ptr: *mut Series) -> *const c_char {
    if s_ptr.is_null() {
        return ptr::null();
    }

    unsafe {
        let s = &*s_ptr;
        if let Ok(c_string) = CString::new(s.name()) {
            c_string.into_raw()
        } else {
            ptr::null()
        }
    }
}

#[no_mangle]
pub extern "C" fn series_rename(s_ptr: *mut Series, new_name: *const c_char) {
    if s_ptr.is_null() || new_name.is_null() {
        return;
    }

    unsafe {
        let s = &mut *s_ptr;
        let c_str = CStr::from_ptr(new_name);
        if let Ok(str_slice) = c_str.to_str() {
            s.rename(str_slice);
        }
    }
}

#[no_mangle]
pub extern "C" fn series_len(s_ptr: *mut Series) -> usize {
    if s_ptr.is_null() {
        0
    } else {
        unsafe {
            let s = &*s_ptr;
            s.len()
        }
    }
}

#[no_mangle]
pub extern "C" fn series_null_count(s_ptr: *mut Series) -> usize {
    if s_ptr.is_null() {
        0
    } else {
        unsafe {
            let s = &*s_ptr;
            s.null_count()
        }
    }
}

#[no_mangle]
pub extern "C" fn series_new_i32(
    name: *const c_char,
    data: *const i32,
    length: usize,
) -> *mut Series {
    if name.is_null() || data.is_null() {
        return ptr::null_mut();
    }

    unsafe {
        let c_str = CStr::from_ptr(name);
        if let Ok(str_slice) = c_str.to_str() {
            let slice = std::slice::from_raw_parts(data, length);
            let s = Series::new(str_slice, slice);
            let boxed_s = Box::new(s);
            Box::into_raw(boxed_s)
        } else {
            ptr::null_mut()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    #[test]
    fn test_series_name_non_null() {
        let series = series_make();
        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "example");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_name_null() {
        let name_ptr = series_name(ptr::null_mut());
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
        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_rename_series_non_null() {
        let series = series_make();

        let new_name = CString::new("new_name").unwrap();
        let new_name_ptr = new_name.as_ptr();

        series_rename(series, new_name_ptr);

        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "new_name");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_rename_series_with_empty_string() {
        let series = series_make();

        let new_name = CString::new("").unwrap();
        let new_name_ptr = new_name.as_ptr();

        series_rename(series, new_name_ptr);

        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_rename_series_null_series_pointer() {
        let new_name = CString::new("new_name").unwrap();
        let new_name_ptr = new_name.as_ptr();

        series_rename(ptr::null_mut(), new_name_ptr);
    }

    #[test]
    fn test_rename_series_null_new_name_pointer() {
        let series = series_make();

        series_rename(series, ptr::null());

        // Ensure the original name remains unchanged
        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "example");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

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

    #[test]
    fn test_series_new_i32_valid() {
        let data = vec![1, 2, 3, 4];
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
        let data = vec![1, 2, 3, 4];
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
}
