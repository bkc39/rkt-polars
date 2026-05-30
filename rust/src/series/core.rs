use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn series_make() -> *mut Series {
    let s = Series::new("example", &[1, 2, 3, 4]);
    let boxed_s = Box::new(s);
    Box::into_raw(boxed_s)
}

#[no_mangle]
pub extern "C" fn series_empty() -> *mut Series {
    Box::into_raw(Box::new(Series::new_empty("", &DataType::Int32)))
}

#[no_mangle]
pub extern "C" fn series_drop(s_ptr: *mut Series) {
    if !s_ptr.is_null() {
        unsafe { drop(Box::from_raw(s_ptr)) };
    }
}

#[no_mangle]
pub extern "C" fn series_name(s_ptr: *mut Series) -> *const c_char {
    if s_ptr.is_null() {
        return ptr::null();
    }

    unsafe { rust_string_to_ptr((*s_ptr).name()) }
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
pub extern "C" fn series_rename(s_ptr: *mut Series, new_name: *const c_char) {
    if s_ptr.is_null() || new_name.is_null() {
        return;
    }

    unsafe {
        let s = &mut *s_ptr;
        let c_str = CStr::from_ptr(new_name);
        if let Ok(str_slice) = c_str.to_str() {
            s.rename(str_slice);
        }
    }
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

pub(crate) fn create_chunked_array_from_raw<T>(
    name: *const c_char,
    data: *const T::Native,
    length: usize,
) -> ChunkedArray<T>
where
    T: PolarsNumericType,
{
    let slice = unsafe { std::slice::from_raw_parts(data as *const _, length) };
    let vec = slice.to_vec();

    unsafe {
        if let Ok(name) = CStr::from_ptr(name).to_str() {
            ChunkedArray::from_vec(name, vec)
        } else {
            ChunkedArray::from_vec("", vec)
        }
    }
}

pub(crate) fn series_new<T>(
    name: *const c_char,
    data: *const T::Native,
    length: usize,
) -> *mut Series
where
    T: PolarsNumericType + Clone,
    ChunkedArray<T>: IntoSeries,
{
    if name.is_null() || data.is_null() {
        return ptr::null_mut();
    }

    let s = create_chunked_array_from_raw(name, data, length);
    Box::into_raw(Box::new(s.into()))
}

pub(crate) fn valid_slices<'a, T>(
    data: *const T,
    valid: *const u8,
    length: usize,
) -> Option<(&'a [T], &'a [u8])> {
    if (data.is_null() || valid.is_null()) && length != 0 {
        return None;
    }
    let values = if length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(data, length) }
    };
    let valid = if length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(valid, length) }
    };
    Some((values, valid))
}
