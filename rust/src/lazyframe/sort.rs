use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_sort(
    lf: *mut LazyFrame,
    by_ptrs: *const *const c_char,
    descending_ptr: *const u8,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(by_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let descending: Vec<bool> = if n == 0 {
        Vec::new()
    } else if descending_ptr.is_null() {
        vec![false; n]
    } else {
        unsafe { std::slice::from_raw_parts(descending_ptr, n) }
            .iter()
            .map(|&b| b != 0)
            .collect()
    };
    let by_exprs: Vec<Expr> = names.iter().map(|n| col(n)).collect();
    let opts =
        SortMultipleOptions::new().with_order_descending_multi(descending);
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.sort_by_exprs(by_exprs, opts)))
}
