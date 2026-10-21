use crate::prelude::*;
use crate::{
    clear_last_error, guard_panic, record, set_last_error, slice_or_empty,
};

#[no_mangle]
pub extern "C" fn dataframe_hstack(
    df_ptr: *mut DataFrame,
    series_ptrs: *const *const Series,
    length: usize,
) -> *mut DataFrame {
    clear_last_error();
    let Some(df) = (unsafe { df_ptr.as_ref() }) else {
        set_last_error("dataframe is null");
        return ptr::null_mut();
    };
    let Some(slice) = (unsafe { slice_or_empty(series_ptrs, length) }) else {
        set_last_error("series list is null");
        return ptr::null_mut();
    };
    if slice.iter().any(|p| p.is_null()) {
        set_last_error("series is null");
        return ptr::null_mut();
    }
    guard_panic(|| {
        let columns: Vec<Column> = slice
            .iter()
            .map(|&p| unsafe { (*p).clone() }.into_column())
            .collect();
        record(if df.width() == 0 {
            DataFrame::new_infer_height(columns)
        } else {
            df.hstack(&columns)
        })
    })
    .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

#[no_mangle]
pub extern "C" fn dataframe_vstack(
    a_ptr: *mut DataFrame,
    b_ptr: *mut DataFrame,
) -> *mut DataFrame {
    clear_last_error();
    let (Some(a), Some(b)) =
        (unsafe { a_ptr.as_ref() }, unsafe { b_ptr.as_ref() })
    else {
        set_last_error("dataframe is null");
        return ptr::null_mut();
    };
    guard_panic(|| record(a.vstack(b)))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}
