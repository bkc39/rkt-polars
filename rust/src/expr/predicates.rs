use crate::prelude::*;

expr_binop!(expr_is_in, |a, b| a.is_in(b));
expr_unop!(expr_is_unique, |e| e.is_unique());
expr_unop!(expr_is_duplicated, |e| e.is_duplicated());
expr_unop!(expr_is_first_distinct, |e| e.is_first_distinct());
expr_unop!(expr_is_last_distinct, |e| e.is_last_distinct());

/// `is_between` with a `closed` selector: 0 = both, 1 = left, 2 = right,
/// 3 = none (any other value treated as `both`).
#[no_mangle]
pub extern "C" fn expr_is_between(
    e: *const Expr,
    lower: *const Expr,
    upper: *const Expr,
    closed: u8,
) -> *mut Expr {
    if e.is_null() || lower.is_null() || upper.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lo = unsafe { (*lower).clone() };
    let hi = unsafe { (*upper).clone() };
    let c = match closed {
        1 => ClosedInterval::Left,
        2 => ClosedInterval::Right,
        3 => ClosedInterval::None,
        _ => ClosedInterval::Both,
    };
    Box::into_raw(Box::new(ee.is_between(lo, hi, c)))
}
