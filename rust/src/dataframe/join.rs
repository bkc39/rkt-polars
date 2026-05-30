use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn dataframe_unique(df_ptr: *mut DataFrame) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    match df.unique(None, polars::prelude::UniqueKeepStrategy::Any, None) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_drop_nulls(
    df_ptr: *mut DataFrame,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let none: Option<&[String]> = None;
    match df.drop_nulls(none) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatJoinKind {
    Inner = 1,
    Left = 2,
    Outer = 3,
    Cross = 4,
    Semi = 5,
    Anti = 6,
}

#[no_mangle]
pub extern "C" fn dataframe_join(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on_ptrs: *const *const c_char,
    n_left_on: usize,
    right_on_ptrs: *const *const c_char,
    n_right_on: usize,
    how: i32,
) -> *mut DataFrame {
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    if how == CompatJoinKind::Cross as i32 {
        use polars::prelude::CrossJoin;
        return match left.cross_join(right, None, None) {
            Ok(out) => Box::into_raw(Box::new(out)),
            Err(_) => ptr::null_mut(),
        };
    }
    let join_type = match how {
        x if x == CompatJoinKind::Inner as i32 => {
            polars::prelude::JoinType::Inner
        }
        x if x == CompatJoinKind::Left as i32 => {
            polars::prelude::JoinType::Left
        }
        x if x == CompatJoinKind::Outer as i32 => {
            polars::prelude::JoinType::Full
        }
        x if x == CompatJoinKind::Semi as i32 => {
            polars::prelude::JoinType::Semi
        }
        x if x == CompatJoinKind::Anti as i32 => {
            polars::prelude::JoinType::Anti
        }
        _ => return ptr::null_mut(),
    };
    let left_on = match unsafe { collect_c_strings(left_on_ptrs, n_left_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let right_on = match unsafe { collect_c_strings(right_on_ptrs, n_right_on) }
    {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if left_on.is_empty() || right_on.is_empty() {
        return ptr::null_mut();
    }
    let args = polars::prelude::JoinArgs::new(join_type);
    match left.join(right, &left_on, &right_on, args) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}
