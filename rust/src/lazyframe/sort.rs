use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_sort_with_options(
    lf: *mut LazyFrame,
    by_ptrs: *const *const c_char,
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let opts = match unsafe {
        sort_multiple_options(descending, nulls_last, n, maintain_order)
    } {
        Ok(o) => o,
        Err(_) => return ptr::null_mut(),
    };
    let names = match unsafe { collect_c_strings(by_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let by_exprs: Vec<Expr> = names.iter().map(|n| col(n.as_str())).collect();
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.sort_by_exprs(by_exprs, opts)))
}
