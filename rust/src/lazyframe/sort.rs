use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_sort_with_options_v2(
    lf: *const LazyFrame,
    by: StrListArg,
    descending: *const u8,
    nulls_last: *const u8,
    n: usize,
    maintain_order: u8,
) -> *mut LazyFrame {
    boxed_unguarded(|| {
        let lf = unsafe { deref_arg(lf, "lazyframe") }?;
        let (names, opts) = unsafe {
            named_sort(by, descending, nulls_last, n, maintain_order)
        }?;
        let by_exprs: Vec<Expr> = names.into_iter().map(col).collect();
        Ok(lf.clone().sort_by_exprs(by_exprs, opts))
    })
}
