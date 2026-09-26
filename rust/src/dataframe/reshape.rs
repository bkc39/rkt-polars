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

pub(crate) fn compat_pivot_agg(code: i32) -> Option<Expr> {
    match code {
        x if x == CompatPivotAgg::None as i32 => Some(element().item(true)),
        x if x == CompatPivotAgg::First as i32 => Some(element().first()),
        x if x == CompatPivotAgg::Sum as i32 => Some(element().sum()),
        x if x == CompatPivotAgg::Min as i32 => Some(element().min()),
        x if x == CompatPivotAgg::Max as i32 => Some(element().max()),
        x if x == CompatPivotAgg::Mean as i32 => Some(element().mean()),
        x if x == CompatPivotAgg::Count as i32 => Some(element().len()),
        _ => None,
    }
}

// Eager pivot is a lazy pivot over the distinct `on` values, sorted, as
// Python's DataFrame.pivot(sort_columns=True) does.
fn pivot_eager(
    df: &DataFrame,
    on: Vec<String>,
    index: Vec<String>,
    values: Vec<String>,
    agg: Expr,
) -> PolarsResult<DataFrame> {
    let on_columns = df
        .select(on.iter())?
        .unique_stable(None, UniqueKeepStrategy::First, None)?
        .sort(on.iter(), SortMultipleOptions::default())?;
    let on_sel = cols(on.clone());
    let index_sel = if index.is_empty() {
        all() - on_sel.clone() - cols(values.clone())
    } else {
        cols(index.clone())
    };
    let values_sel = if values.is_empty() {
        all() - on_sel.clone() - index_sel.clone()
    } else {
        cols(values)
    };
    df.clone()
        .lazy()
        .pivot(
            on_sel,
            Arc::new(on_columns),
            index_sel,
            values_sel,
            agg,
            true,
            "_".into(),
            polars::frame::PivotColumnNaming::Auto,
        )
        .collect()
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
    match pivot_eager(df, on, index, values, agg_expr) {
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
    let on = if on.is_empty() { None } else { Some(on) };
    match df.unpivot(on, index) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}
