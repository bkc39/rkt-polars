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
        let opts = unsafe {
            sort_multiple_options(descending, nulls_last, n, maintain_order)
        }
        .map_err(|cause| polars_err!(ComputeError: "{}", cause))?;
        let names = sort_keys(unsafe { str_list_arg(by) }?, n)?;
        let by_exprs: Vec<Expr> = names.into_iter().map(col).collect();
        Ok(lf.clone().sort_by_exprs(by_exprs, opts))
    })
}
