use crate::prelude::*;
use crate::*;
use std::sync::atomic::{AtomicUsize, Ordering};

static DROPPED: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn series_drop_count() -> usize {
    DROPPED.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn series_make() -> *mut Series {
    let s = Series::new("example".into(), &[1, 2, 3, 4]);
    let boxed_s = Box::new(s);
    Box::into_raw(boxed_s)
}

#[no_mangle]
pub extern "C" fn series_empty() -> *mut Series {
    Box::into_raw(Box::new(Series::new_empty(
        PlSmallStr::EMPTY,
        &DataType::Int32,
    )))
}

#[no_mangle]
pub extern "C" fn series_drop(s_ptr: *mut Series) {
    if !s_ptr.is_null() {
        unsafe { drop(Box::from_raw(s_ptr)) };
        DROPPED.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn series_name_v2(s_ptr: *const Series) -> StrOut {
    unsafe { s_ptr.as_ref() }.map_or(ptr::null_mut(), |s| str_out(s.name()))
}

#[no_mangle]
pub extern "C" fn series_dtype(s_ptr: *mut Series) -> CompatDType {
    if s_ptr.is_null() {
        return CompatDType {
            tag: CompatDTypeTag::Unknown as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        };
    }

    unsafe { compat_dtype_from_polars((*s_ptr).dtype()) }
}

#[no_mangle]
pub extern "C" fn series_rename_v2(s_ptr: *mut Series, name: StrArg) -> i32 {
    scalar_result(-1, || {
        let s = unsafe { s_ptr.as_mut() }
            .ok_or_else(|| polars_err!(ComputeError: "series is null"))?;
        s.rename(unsafe { name_arg(name, "the name") }?.into());
        Ok(0)
    })
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

pub(crate) fn series_new<T>(
    name: *const c_char,
    data: *const T::Native,
    length: usize,
) -> *mut Series
where
    T: PolarsNumericType,
    ChunkedArray<T>: IntoSeries,
{
    if name.is_null() {
        return ptr::null_mut();
    }
    let Some(values) = (unsafe { slice_or_empty(data, length) }) else {
        return ptr::null_mut();
    };
    let ca = ChunkedArray::<T>::from_vec(name_from_ptr(name), values.to_vec());
    Box::into_raw(Box::new(ca.into_series()))
}

pub(crate) fn valid_slices<'a, T>(
    data: *const T,
    valid: *const u8,
    length: usize,
) -> Option<(&'a [T], &'a [u8])> {
    unsafe {
        Some((
            slice_or_empty(data, length)?,
            slice_or_empty(valid, length)?,
        ))
    }
}
