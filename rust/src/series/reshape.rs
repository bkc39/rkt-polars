use crate::prelude::*;
use crate::{clear_last_error, guard_panic, record, set_last_error};
use polars::series::IsSorted;

#[no_mangle]
pub extern "C" fn series_head(s_ptr: *mut Series, n: usize) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.head(Some(n))))
}

#[no_mangle]
pub extern "C" fn series_tail(s_ptr: *mut Series, n: usize) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.tail(Some(n))))
}

#[no_mangle]
pub extern "C" fn series_slice(
    s_ptr: *mut Series,
    offset: i64,
    length: usize,
) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.slice(offset, length)))
}

#[no_mangle]
pub extern "C" fn series_reverse(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.reverse()))
}

#[no_mangle]
pub extern "C" fn series_drop_nulls(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.drop_nulls()))
}

#[no_mangle]
pub extern "C" fn series_unique(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    match s.unique() {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_sort_with_options(
    s_ptr: *mut Series,
    descending: u8,
    nulls_last: u8,
) -> *mut Series {
    clear_last_error();
    if s_ptr.is_null() {
        set_last_error("series is null");
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    let opts = SortOptions::default()
        .with_order_descending(descending != 0)
        .with_nulls_last(nulls_last != 0);
    guard_panic(|| record(sort_series(s, opts)))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

/// polars 0.41.3's `sort_with` panics on a nulls-last boolean sort, puts the
/// nulls of a descending boolean sort last, and returns a column flagged as
/// sorted unchanged when nulls-last is asked of it. Booleans take `arg_sort`,
/// which has none of these defects; a nulls-last sort drops the flag first.
pub(crate) fn sort_series(
    s: &Series,
    opts: SortOptions,
) -> PolarsResult<Series> {
    if s.dtype() == &DataType::Boolean && (opts.descending || opts.nulls_last) {
        s.take(&s.arg_sort(opts))
    } else if opts.nulls_last {
        let mut unflagged = s.clone();
        unflagged.set_sorted_flag(IsSorted::Not);
        unflagged.sort_with(opts)
    } else {
        s.sort_with(opts)
    }
}
