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
pub extern "C" fn expr_exclude(
    e: *const Expr,
    names: *const *const c_char,
    n: usize,
) -> *mut Expr {
    if e.is_null() || n == 0 {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(names, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let ee = unsafe { (*e).clone() };
    if !is_multi_column(&ee) {
        return ptr::null_mut();
    }
    let out = ee.map_expr(|x| match x {
        Expr::Selector(s) => {
            Expr::Selector(s - by_name(names.clone(), false, true))
        }
        other => other,
    });
    Box::into_raw(Box::new(out))
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
