use crate::prelude::*;
use crate::{
    clear_last_error, guard_panic, record, rust_string_to_ptr, set_last_error,
};

#[no_mangle]
pub extern "C" fn lazyframe_drop(lf: *mut LazyFrame) {
    if !lf.is_null() {
        unsafe { drop(Box::from_raw(lf)) };
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

#[no_mangle]
pub extern "C" fn lazyframe_collect(lf: *mut LazyFrame) -> *mut DataFrame {
    clear_last_error();
    if lf.is_null() {
        set_last_error("lazyframe is null");
        return ptr::null_mut();
    }
    let owned = unsafe { (*lf).clone() };
    guard_panic(|| record(owned.collect()))
        .map_or(ptr::null_mut(), |df| Box::into_raw(Box::new(df)))
}

#[no_mangle]
pub extern "C" fn lazyframe_explain(
    lf: *mut LazyFrame,
    optimized: bool,
    tree: bool,
) -> *const c_char {
    clear_last_error();
    if lf.is_null() {
        set_last_error("lazyframe is null");
        return ptr::null();
    }
    let lf = unsafe { &*lf };
    guard_panic(|| {
        record(match (optimized, tree) {
            (true, false) => lf.describe_optimized_plan(),
            (true, true) => lf.describe_optimized_plan_tree(),
            (false, false) => lf.describe_plan(),
            (false, true) => lf.describe_plan_tree(),
        })
    })
    .map_or(ptr::null(), |plan| {
        let text = rust_string_to_ptr(plan);
        if text.is_null() {
            set_last_error("the plan's text holds a NUL character");
        }
        text
    })
}
