use crate::prelude::*;

/// Conditional expression: parallel `conds` / `vals` arrays of length `n`
/// plus a final `otherwise`. Lowered as nested
/// `when(c0).then(v0).otherwise(when(c1).then(v1).otherwise(... otherwise)))`,
/// which is semantically the chained `when().then()...otherwise()` form.
#[no_mangle]
pub extern "C" fn expr_when_then(
    conds: *const *const Expr,
    vals: *const *const Expr,
    n: usize,
    otherwise: *const Expr,
) -> *mut Expr {
    if conds.is_null() || vals.is_null() || otherwise.is_null() || n == 0 {
        return ptr::null_mut();
    }
    let conds = unsafe { std::slice::from_raw_parts(conds, n) };
    let vals = unsafe { std::slice::from_raw_parts(vals, n) };
    if conds.iter().chain(vals.iter()).any(|p| p.is_null()) {
        return ptr::null_mut();
    }
    let mut acc = unsafe { (*otherwise).clone() };
    for i in (0..n).rev() {
        let c = unsafe { (*conds[i]).clone() };
        let v = unsafe { (*vals[i]).clone() };
        acc = when(c).then(v).otherwise(acc);
    }
    Box::into_raw(Box::new(acc))
}
