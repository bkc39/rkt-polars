use crate::prelude::*;
use crate::{boxed_result, deref_arg, slice_or_empty};
use std::sync::atomic::{AtomicUsize, Ordering};

static DROPPED: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn dataframe_drop_count() -> usize {
    DROPPED.load(Ordering::Relaxed)
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
        DROPPED.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn dataframe_new(
    series_ptrs: *const *const Series,
    length: usize,
) -> *mut DataFrame {
    let Some(slice) = (unsafe { slice_or_empty(series_ptrs, length) }) else {
        return ptr::null_mut();
    };
    if slice.iter().any(|p| p.is_null()) {
        return ptr::null_mut();
    }
    let columns: Vec<Column> = slice
        .iter()
        .map(|&p| unsafe { (*p).clone() }.into_column())
        .collect();
    match DataFrame::new_infer_height(columns) {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_height(df_ptr: *mut DataFrame) -> usize {
    if df_ptr.is_null() {
        0
    } else {
        unsafe { (*df_ptr).height() }
    }
}

#[no_mangle]
pub extern "C" fn dataframe_width(df_ptr: *mut DataFrame) -> usize {
    if df_ptr.is_null() {
        0
    } else {
        unsafe { (*df_ptr).width() }
    }
}

#[no_mangle]
pub extern "C" fn dataframe_head(
    df_ptr: *mut DataFrame,
    n: usize,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        Ok(df.head(Some(n)))
    })
}

#[no_mangle]
pub extern "C" fn dataframe_tail(
    df_ptr: *mut DataFrame,
    n: usize,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        Ok(df.tail(Some(n)))
    })
}

#[no_mangle]
pub extern "C" fn dataframe_slice(
    df_ptr: *mut DataFrame,
    offset: i64,
    length: usize,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        Ok(df.slice(offset, length))
    })
}
