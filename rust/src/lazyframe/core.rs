use crate::prelude::*;
use crate::{
    clear_last_error, guard_panic, record, set_last_error, str_out,
    without_plan, StrOut,
};
use std::sync::atomic::{AtomicUsize, Ordering};

static DROPPED: AtomicUsize = AtomicUsize::new(0);

#[no_mangle]
pub extern "C" fn lazyframe_drop_count() -> usize {
    DROPPED.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn lazyframe_drop(lf: *mut LazyFrame) {
    if !lf.is_null() {
        unsafe { drop(Box::from_raw(lf)) };
        DROPPED.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn dataframe_lazy(df: *mut DataFrame) -> *mut LazyFrame {
    if df.is_null() {
        return ptr::null_mut();
    }
    let cloned = unsafe { (*df).clone() };
    Box::into_raw(Box::new(cloned.lazy()))
}

/// The innermost error, without the step names polars wraps it in or the
/// plan it appends.
pub(crate) fn cause_alone(err: PolarsError) -> PolarsError {
    match err {
        PolarsError::Context { error, .. } => cause_alone(*error),
        err => without_plan(err),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_collect(lf: *mut LazyFrame) -> *mut DataFrame {
    clear_last_error();
    if lf.is_null() {
        set_last_error("lazyframe is null");
        return ptr::null_mut();
    }
    let owned = unsafe { (*lf).clone() };
    guard_panic(|| record(owned.collect().map_err(cause_alone)))
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
}

#[no_mangle]
pub extern "C" fn lazyframe_explain_v2(
    lf: *const LazyFrame,
    optimized: bool,
    tree: bool,
) -> StrOut {
    clear_last_error();
    if lf.is_null() {
        set_last_error("lazyframe is null");
        return ptr::null_mut();
    }
    let lf = unsafe { &*lf };
    guard_panic(|| {
        record(
            match (optimized, tree) {
                (true, false) => lf.describe_optimized_plan(),
                (true, true) => lf.describe_optimized_plan_tree(),
                (false, false) => lf.describe_plan(),
                (false, true) => lf.describe_plan_tree(),
            }
            .map_err(cause_alone),
        )
    })
    .map_or(ptr::null_mut(), |plan| str_out(&plan))
}
