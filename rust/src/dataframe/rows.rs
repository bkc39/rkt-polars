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
pub extern "C" fn dataframe_sort_with_options_v2(
    df_ptr: *const DataFrame,
    by: StrListArg,
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        let (names, opts) = unsafe {
            named_sort(by, descending, nulls_last, n, maintain_order)
        }?;
        df.sort(names, opts)
    })
}
