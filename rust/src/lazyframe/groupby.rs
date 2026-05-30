use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_group_by_agg(
    lf: *mut LazyFrame,
    key_ptrs: *const *const Expr,
    n_keys: usize,
    agg_ptrs: *const *const Expr,
    n_aggs: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let keys = match unsafe { collect_exprs(key_ptrs, n_keys) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let aggs = match unsafe { collect_exprs(agg_ptrs, n_aggs) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.group_by(keys).agg(aggs)))
}

// ===== Phase A6: more LazyFrame ops (sort / unique / drop_nulls) =====
