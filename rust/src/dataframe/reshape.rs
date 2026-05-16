use crate::prelude::*;
use crate::*;

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatPivotAgg {
    None = 0,
    First = 1,
    Sum = 2,
    Min = 3,
    Max = 4,
    Mean = 5,
    Count = 6,
}

pub(crate) fn compat_pivot_agg(code: i32) -> Option<Option<Expr>> {
    match code {
        x if x == CompatPivotAgg::None as i32 => Some(None),
        x if x == CompatPivotAgg::First as i32 => Some(Some(first())),
        x if x == CompatPivotAgg::Sum as i32 => Some(Some(col("").sum())),
        x if x == CompatPivotAgg::Min as i32 => Some(Some(col("").min())),
        x if x == CompatPivotAgg::Max as i32 => Some(Some(col("").max())),
        x if x == CompatPivotAgg::Mean as i32 => Some(Some(col("").mean())),
        x if x == CompatPivotAgg::Count as i32 => Some(Some(col("").count())),
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_pivot(
    df_ptr: *mut DataFrame,
    on_ptrs: *const *const c_char,
    n_on: usize,
    index_ptrs: *const *const c_char,
    n_index: usize,
    values_ptrs: *const *const c_char,
    n_values: usize,
    agg: i32,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let on = match unsafe { collect_c_strings(on_ptrs, n_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if on.is_empty() {
        return ptr::null_mut();
    }
    let index = match unsafe { collect_c_strings(index_ptrs, n_index) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let values = match unsafe { collect_c_strings(values_ptrs, n_values) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let agg_expr = match compat_pivot_agg(agg) {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    match polars::lazy::frame::pivot::pivot_stable(
        df,
        on,
        Some(index),
        Some(values),
        true,
        agg_expr,
        None,
    ) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_unpivot(
    df_ptr: *mut DataFrame,
    on_ptrs: *const *const c_char,
    n_on: usize,
    index_ptrs: *const *const c_char,
    n_index: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let on = match unsafe { collect_c_strings(on_ptrs, n_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let index = match unsafe { collect_c_strings(index_ptrs, n_index) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    match df.unpivot(on, index) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}
