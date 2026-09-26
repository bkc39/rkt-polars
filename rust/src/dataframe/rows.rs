use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn dataframe_filter(
    df_ptr: *mut DataFrame,
    mask_ptr: *mut Series,
) -> *mut DataFrame {
    if df_ptr.is_null() || mask_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let mask = unsafe { &*mask_ptr };
    let bool_ca = match mask.bool() {
        Ok(ca) => ca,
        Err(_) => return ptr::null_mut(),
    };
    match df.filter(bool_ca) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_sort_with_options(
    df_ptr: *mut DataFrame,
    by_ptrs: *const *const c_char,
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> *mut DataFrame {
    clear_last_error();
    if df_ptr.is_null() {
        set_last_error("dataframe is null");
        return ptr::null_mut();
    }
    let opts = match record(unsafe {
        sort_multiple_options(descending, nulls_last, n, maintain_order)
    }) {
        Some(o) => o,
        None => return ptr::null_mut(),
    };
    let names = match unsafe { collect_c_strings(by_ptrs, n) } {
        Some(v) => v,
        None => {
            set_last_error("sort keys are not valid strings");
            return ptr::null_mut();
        }
    };
    let df = unsafe { &*df_ptr };
    guard_panic(|| record(sort_frame(df, names, opts)))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

/// polars sorts a frame of width 1 by its own column with `sort_with`, whose
/// defects `sort_series` routes around.
fn sort_frame(
    df: &DataFrame,
    names: Vec<String>,
    opts: SortMultipleOptions,
) -> PolarsResult<DataFrame> {
    let by = df.select_series(names)?;
    if let [key] = by.as_slice() {
        if df.width() == 1 {
            return Ok(sort_series(key, SortOptions::from(&opts))?.into_frame());
        }
    }
    df.sort_impl(by, opts, None)
}
