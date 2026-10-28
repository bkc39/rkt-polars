use crate::prelude::*;
use crate::*;

/// `expr_exclude` subtracts the names from each selector in the expression;
/// an expression with no multi-column selector would drop them silently, so
/// it is refused.
fn is_multi_column(e: &Expr) -> bool {
    e.into_iter().any(|x| match x {
        Expr::Selector(Selector::ByIndex { indices, .. }) => indices.len() > 1,
        Expr::Selector(_) => true,
        _ => false,
    })
}

#[no_mangle]
pub extern "C" fn expr_all() -> *mut Expr {
    Box::into_raw(Box::new(all().as_expr()))
}

#[no_mangle]
pub extern "C" fn expr_multi_column(e: *const Expr) -> u8 {
    if e.is_null() {
        return 0;
    }
    is_multi_column(unsafe { &*e }) as u8
}

#[no_mangle]
pub extern "C" fn expr_exclude_v2(
    e: *const Expr,
    names: StrListArg,
) -> *mut Expr {
    boxed_unguarded(|| {
        let e = unsafe { deref_arg(e, "expression") }?;
        let names: Vec<PlSmallStr> = unsafe { str_list_arg(names) }?
            .into_iter()
            .map(PlSmallStr::from)
            .collect();
        polars_ensure!(!names.is_empty(), ComputeError: "exclude needs a name");
        polars_ensure!(
            is_multi_column(e),
            ComputeError: "exclude needs a multi-column expression"
        );
        Ok(e.clone().map_expr(|x| match x {
            Expr::Selector(s) => {
                Expr::Selector(s - by_name(names.clone(), false, true))
            }
            other => other,
        }))
    })
}

#[no_mangle]
pub extern "C" fn expr_dtype_col(target: CompatDType) -> *mut Expr {
    match polars_dtype_from_compat(&target) {
        Some(dt) => {
            Box::into_raw(Box::new(dtype_col(&dt).as_selector().as_expr()))
        }
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn expr_dtype_col_enum(
    categories: *const *const c_char,
    n: usize,
) -> *mut Expr {
    clear_last_error();
    enum_dtype(categories, n).map_or(ptr::null_mut(), |dt| {
        Box::into_raw(Box::new(dtype_col(&dt).as_selector().as_expr()))
    })
}

#[no_mangle]
pub extern "C" fn expr_dtype_col_datetime_tz(
    unit: i32,
    tz: *const c_char,
) -> *mut Expr {
    clear_last_error();
    datetime_tz_dtype(unit, tz).map_or(ptr::null_mut(), |dt| {
        Box::into_raw(Box::new(dtype_col(&dt).as_selector().as_expr()))
    })
}
