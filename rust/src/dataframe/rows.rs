use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn dataframe_filter(
    df_ptr: *mut DataFrame,
    mask_ptr: *mut Series,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        let mask = unsafe { deref_arg(mask_ptr, "mask") }?;
        df.filter(mask.bool()?)
    })
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
