use crate::prelude::*;

pub(crate) fn series_arith_result<F>(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
    f: F,
) -> *mut Series
where
    F: FnOnce(&Series, &Series) -> PolarsResult<Series>,
{
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    match f(left, right) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_add(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Add::add(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_sub(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Sub::sub(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_mul(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Mul::mul(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_div(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Div::div(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_mod(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Rem::rem(left, right)
    })
}

macro_rules! arith_scalar {
    ($name:ident, $op:path, $downcast:ident, $rhs_ty:ty) => {
        #[no_mangle]
        pub extern "C" fn $name(
            s_ptr: *mut Series,
            rhs: $rhs_ty,
        ) -> *mut Series {
            if s_ptr.is_null() {
                return ptr::null_mut();
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => Box::into_raw(Box::new($op(ca, rhs).into_series())),
                Err(_) => ptr::null_mut(),
            }
        }
    };
}

macro_rules! arith_scalar_family {
    ($downcast:ident, $rhs_ty:ty,
     $add:ident, $sub:ident, $mul:ident, $div:ident, $rem:ident) => {
        arith_scalar!($add, std::ops::Add::add, $downcast, $rhs_ty);
        arith_scalar!($sub, std::ops::Sub::sub, $downcast, $rhs_ty);
        arith_scalar!($mul, std::ops::Mul::mul, $downcast, $rhs_ty);
        arith_scalar!($div, std::ops::Div::div, $downcast, $rhs_ty);
        arith_scalar!($rem, std::ops::Rem::rem, $downcast, $rhs_ty);
    };
}

arith_scalar_family!(
    i32,
    i32,
    series_add_i32,
    series_sub_i32,
    series_mul_i32,
    series_div_i32,
    series_mod_i32
);
arith_scalar_family!(
    i64,
    i64,
    series_add_i64,
    series_sub_i64,
    series_mul_i64,
    series_div_i64,
    series_mod_i64
);
arith_scalar_family!(
    u32,
    u32,
    series_add_u32,
    series_sub_u32,
    series_mul_u32,
    series_div_u32,
    series_mod_u32
);
arith_scalar_family!(
    u64,
    u64,
    series_add_u64,
    series_sub_u64,
    series_mul_u64,
    series_div_u64,
    series_mod_u64
);
arith_scalar_family!(
    f64,
    f64,
    series_add_f64,
    series_sub_f64,
    series_mul_f64,
    series_div_f64,
    series_mod_f64
);

// ===== Track A: Expr / Lazy DSL =====
