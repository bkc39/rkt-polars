use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_join(
    left_ptr: *mut LazyFrame,
    right_ptr: *mut LazyFrame,
    left_on_ptrs: *const *const c_char,
    n_left_on: usize,
    right_on_ptrs: *const *const c_char,
    n_right_on: usize,
    how: i32,
) -> *mut LazyFrame {
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { (*left_ptr).clone() };
    let right = unsafe { (*right_ptr).clone() };
    if how == CompatJoinKind::Cross as i32 {
        return Box::into_raw(Box::new(left.cross_join(right, None)));
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
    let left_exprs: Vec<Expr> = left_on.iter().map(|n| col(n)).collect();
    let right_exprs: Vec<Expr> = right_on.iter().map(|n| col(n)).collect();
    let args = polars::prelude::JoinArgs::new(join_type);
    Box::into_raw(Box::new(left.join(right, left_exprs, right_exprs, args)))
}

// ===== Phase A9: expr cast =====
//
// Takes a CompatDType *by value* (same struct used on the output side
// of `series_dtype`).  Unsupported tags (List/Array/Struct/Decimal/...)
// return null so the Racket side can raise rather than panic.
