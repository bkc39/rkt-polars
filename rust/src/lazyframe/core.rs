use crate::prelude::*;
use crate::{clear_last_error, set_last_error};

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
    const OP: &str = "collect";
    clear_last_error();
    if lf.is_null() {
        set_last_error(format!("{}: lazyframe is null", OP));
        return ptr::null_mut();
    }
    let owned = unsafe { (*lf).clone() };
    // Recorded without a prefix: the caller already says it was collecting, and
    // polars' own message names the step of the plan that failed.
    match owned.collect() {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(err) => {
            set_last_error(err.to_string());
            ptr::null_mut()
        }
    }
}
