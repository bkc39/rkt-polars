use crate::prelude::*;
use crate::*;

fn is_regex_projection(name: &str) -> bool {
    name.starts_with('^') && name.ends_with('$')
}

/// Polars strips an `Exclude` node only while expanding a wildcard, dtype,
/// columns, multi-index or regex leaf (`find_flags` in polars-plan's
/// expr_expansion.rs); one left over panics at plan conversion, so
/// `expr_exclude` refuses any other input.
fn is_multi_column(e: &Expr) -> bool {
    e.into_iter().any(|x| match x {
        Expr::Wildcard | Expr::DtypeColumn(_) | Expr::Columns(_) => true,
        Expr::IndexColumn(idx) => idx.len() > 1,
        Expr::Column(name) => is_regex_projection(name),
        _ => false,
    })
}

#[no_mangle]
pub extern "C" fn expr_all() -> *mut Expr {
    Box::into_raw(Box::new(all()))
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
    Box::into_raw(Box::new(ee.exclude(names)))
}

#[no_mangle]
pub extern "C" fn expr_dtype_col(target: CompatDType) -> *mut Expr {
    match polars_dtype_from_compat(&target) {
        Some(dt) => Box::into_raw(Box::new(dtype_col(&dt))),
        None => ptr::null_mut(),
    }
}
