use crate::prelude::*;
use crate::{
    boxed_result, clear_last_error, deref_arg, guard_panic, record,
    set_last_error,
};

macro_rules! cmp_scalar {
    ($name:ident, $op:ident, $downcast:ident, $rhs_ty:ty) => {
        #[no_mangle]
        pub extern "C" fn $name(
            s_ptr: *mut Series,
            rhs: $rhs_ty,
        ) -> *mut Series {
            boxed_result(|| {
                let s = unsafe { deref_arg(s_ptr, "series") }?;
                Ok(s.$downcast()?.$op(rhs).into_series())
            })
        }
    };
}

cmp_scalar!(series_lt_i32, lt, i32, i32);
cmp_scalar!(series_le_i32, lt_eq, i32, i32);
cmp_scalar!(series_gt_i32, gt, i32, i32);
cmp_scalar!(series_ge_i32, gt_eq, i32, i32);
cmp_scalar!(series_eq_i32, equal, i32, i32);
cmp_scalar!(series_ne_i32, not_equal, i32, i32);

cmp_scalar!(series_lt_f64, lt, f64, f64);
cmp_scalar!(series_le_f64, lt_eq, f64, f64);
cmp_scalar!(series_gt_f64, gt, f64, f64);
cmp_scalar!(series_ge_f64, gt_eq, f64, f64);
cmp_scalar!(series_eq_f64, equal, f64, f64);
cmp_scalar!(series_ne_f64, not_equal, f64, f64);

#[no_mangle]
pub extern "C" fn series_is_null(s_ptr: *mut Series) -> *mut Series {
    boxed_result(|| {
        let s = unsafe { deref_arg(s_ptr, "series") }?;
        Ok(s.is_null().into_series())
    })
}

#[no_mangle]
pub extern "C" fn series_is_not_null(s_ptr: *mut Series) -> *mut Series {
    boxed_result(|| {
        let s = unsafe { deref_arg(s_ptr, "series") }?;
        Ok(s.is_not_null().into_series())
    })
}

pub(crate) fn series_cmp_result<F>(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
    f: F,
) -> *mut Series
where
    F: FnOnce(&Series, &Series) -> PolarsResult<BooleanChunked>,
{
    clear_last_error();
    let (Some(left), Some(right)) =
        (unsafe { left_ptr.as_ref() }, unsafe { right_ptr.as_ref() })
    else {
        set_last_error("series is null");
        return ptr::null_mut();
    };
    guard_panic(|| record(f(left, right))).map_or(ptr::null_mut(), |out| {
        Box::into_raw(Box::new(out.into_series()))
    })
}

#[no_mangle]
pub extern "C" fn series_eq(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.equal(right))
}

#[no_mangle]
pub extern "C" fn series_ne(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.not_equal(right))
}

#[no_mangle]
pub extern "C" fn series_gt(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.gt(right))
}

#[no_mangle]
pub extern "C" fn series_ge(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.gt_eq(right))
}

#[no_mangle]
pub extern "C" fn series_lt(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.lt(right))
}

#[no_mangle]
pub extern "C" fn series_le(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.lt_eq(right))
}
