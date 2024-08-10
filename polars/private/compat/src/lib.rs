use polars::prelude::*;

/// A struct to represent a tuple (usize, usize) for C FFI
#[repr(C)]
pub struct Shape {
    pub rows: usize,
    pub cols: usize,
}

#[no_mangle]
pub extern "C" fn make_dataframe() -> *mut DataFrame {
    let df = DataFrame::default();
    let boxed_df = Box::new(df);
    Box::into_raw(boxed_df)
}

#[no_mangle]
pub extern "C" fn empty_dataframe() -> *mut DataFrame {
    Box::into_raw(Box::new(DataFrame::empty()))
}

#[no_mangle]
pub extern "C" fn free_dataframe(df_ptr: *mut DataFrame) {
    if !df_ptr.is_null() {
        unsafe { drop(Box::from_raw(df_ptr)) };
    }
}

#[no_mangle]
pub extern "C" fn get_shape(df_ptr: *mut DataFrame) -> Shape {
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    #[test]
    fn free_non_null_dataframe() {
        let df = make_dataframe();
        assert!(!df.is_null());
        free_dataframe(df);
    }

    #[test]
    fn free_empty_dataframe() {
        let df = empty_dataframe();
        assert!(!df.is_null());
        free_dataframe(df);
    }

    #[test]
    fn free_null_dataframe() {
        let df: *mut DataFrame = ptr::null_mut();
        free_dataframe(df);
    }
}
