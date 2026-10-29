use crate::prelude::*;
use crate::*;

const ENUM_CAST_FMT: &str = "to_enum";

#[no_mangle]
pub extern "C" fn expr_cast(e: *mut Expr, target: CompatDType) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let dt = match polars_dtype_from_compat(&target) {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    let e_ref = unsafe { (*e).clone() };
    Box::into_raw(Box::new(e_ref.cast(dt)))
}

#[no_mangle]
pub extern "C" fn expr_cast_enum_v2(
    e: *const Expr,
    categories: StrListArg,
) -> *mut Expr {
    clear_last_error();
    let Some(e) = (unsafe { e.as_ref() }) else {
        set_last_error("expression is null");
        return ptr::null_mut();
    };
    enum_dtype(categories).map_or(ptr::null_mut(), |dtype| {
        Box::into_raw(Box::new(enum_cast_expr(e.clone(), dtype)))
    })
}

/// A cast to an Enum that reports its misses as the eager cast does. It is
/// groupwise, not elementwise, so that polars runs it once on the whole
/// column in `select`, `with_columns` and `filter`, never once per chunk.
fn enum_cast_expr(e: Expr, dtype: DataType) -> Expr {
    let field_dtype = dtype.clone();
    e.apply_with_fmt_str(
        move |c: Column| {
            enum_cast_checked(c.as_materialized_series(), &dtype)
                .map(Column::from)
        },
        move |_: &Schema, f: &Field| {
            Ok(Field::new(f.name().clone(), field_dtype.clone()))
        },
        ENUM_CAST_FMT,
    )
}

/// The input of a cast to an Enum, which sorts as the cast it stands for.
pub(crate) fn enum_cast_input(e: &Expr) -> Option<&Expr> {
    match e {
        Expr::AnonymousFunction { input, fmt_str, .. }
            if fmt_str.as_str() == ENUM_CAST_FMT && input.len() == 1 =>
        {
            Some(&input[0])
        }
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn expr_cast_datetime_tz(
    e: *const Expr,
    unit: i32,
    tz: *const c_char,
) -> *mut Expr {
    clear_last_error();
    let Some(e) = (unsafe { e.as_ref() }) else {
        set_last_error("expression is null");
        return ptr::null_mut();
    };
    datetime_tz_dtype(unit, tz).map_or(ptr::null_mut(), |dtype| {
        Box::into_raw(Box::new(e.clone().cast(dtype)))
    })
}
