use crate::prelude::*;

pub extern "C" fn lazyframe_drop(lf: *mut LazyFrame) {
    if !lf.is_null() {
        unsafe { drop(Box::from_raw(lf)) };
    }
}

pub extern "C" fn dataframe_lazy(df: *mut DataFrame) -> *mut LazyFrame {
    if df.is_null() {
        return ptr::null_mut();
    }
    let cloned = unsafe { (*df).clone() };
    Box::into_raw(Box::new(cloned.lazy()))
}

pub extern "C" fn lazyframe_collect(lf: *mut LazyFrame) -> *mut DataFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let owned = unsafe { (*lf).clone() };
    match owned.collect() {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}
