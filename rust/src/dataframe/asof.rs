use crate::prelude::*;
use crate::*;

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatAsofStrategy {
    Backward = 1,
    Forward = 2,
    Nearest = 3,
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatAsofToleranceKind {
    None = 0,
    Integer = 1,
    Float = 2,
}

pub(crate) fn compat_asof_strategy(
    code: i32,
) -> Option<polars::prelude::AsofStrategy> {
    match code {
        x if x == CompatAsofStrategy::Backward as i32 => {
            Some(polars::prelude::AsofStrategy::Backward)
        }
        x if x == CompatAsofStrategy::Forward as i32 => {
            Some(polars::prelude::AsofStrategy::Forward)
        }
        x if x == CompatAsofStrategy::Nearest as i32 => {
            Some(polars::prelude::AsofStrategy::Nearest)
        }
        _ => None,
    }
}

pub(crate) fn compat_asof_tolerance(
    dtype: &DataType,
    kind: i32,
    integer: i64,
    float: f64,
) -> Option<Option<AnyValue<'static>>> {
    use CompatAsofToleranceKind as Kind;
    if kind == Kind::None as i32 {
        return Some(None);
    }
    Some(Some(match (dtype.to_physical(), kind) {
        (DataType::Int32, x) if x == Kind::Integer as i32 => {
            AnyValue::Int32(integer.try_into().ok()?)
        }
        (DataType::Int64, x) if x == Kind::Integer as i32 => {
            AnyValue::Int64(integer)
        }
        (DataType::UInt32, x) if x == Kind::Integer as i32 => {
            AnyValue::UInt32(integer.try_into().ok()?)
        }
        (DataType::UInt64, x) if x == Kind::Integer as i32 => {
            AnyValue::UInt64(integer.try_into().ok()?)
        }
        (DataType::Float32, x) if x == Kind::Float as i32 => {
            AnyValue::Float32(float as f32)
        }
        (DataType::Float64, x) if x == Kind::Float as i32 => {
            AnyValue::Float64(float)
        }
        _ => return None,
    }))
}

#[no_mangle]
pub extern "C" fn dataframe_join_asof(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on: *const c_char,
    right_on: *const c_char,
    strategy: i32,
) -> *mut DataFrame {
    if left_ptr.is_null()
        || right_ptr.is_null()
        || left_on.is_null()
        || right_on.is_null()
    {
        return ptr::null_mut();
    }
    let left_on_str = match unsafe { CStr::from_ptr(left_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_on_str = match unsafe { CStr::from_ptr(right_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let strategy = match compat_asof_strategy(strategy) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    let left_key = match left.column(left_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_key = match right.column(right_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match left._join_asof(
        right, left_key, right_key, strategy, None, None, None, true,
    ) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_join_asof_options(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on: *const c_char,
    right_on: *const c_char,
    strategy: i32,
    left_by_ptrs: *const *const c_char,
    n_left_by: usize,
    right_by_ptrs: *const *const c_char,
    n_right_by: usize,
    tolerance_kind: i32,
    tolerance_integer: i64,
    tolerance_float: f64,
) -> *mut DataFrame {
    if left_ptr.is_null()
        || right_ptr.is_null()
        || left_on.is_null()
        || right_on.is_null()
    {
        return ptr::null_mut();
    }
    let left_on_str = match unsafe { CStr::from_ptr(left_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_on_str = match unsafe { CStr::from_ptr(right_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let strategy = match compat_asof_strategy(strategy) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let left_by = match unsafe { collect_c_strings(left_by_ptrs, n_left_by) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let right_by = match unsafe { collect_c_strings(right_by_ptrs, n_right_by) }
    {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if left_by.len() != right_by.len() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    let left_key = match left.column(left_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_key = match right.column(right_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let tolerance = match compat_asof_tolerance(
        left_key.dtype(),
        tolerance_kind,
        tolerance_integer,
        tolerance_float,
    ) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };
    let result = if left_by.is_empty() && right_by.is_empty() {
        left._join_asof(
            right, left_key, right_key, strategy, tolerance, None, None, true,
        )
    } else {
        left.join_asof_by(
            right,
            left_on_str,
            right_on_str,
            left_by.iter(),
            right_by.iter(),
            strategy,
            tolerance,
        )
    };
    match result {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}
