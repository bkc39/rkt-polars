use crate::prelude::*;
use crate::rust_string_to_ptr;
use std::sync::Arc;

#[no_mangle]
pub extern "C" fn expr_meta_output_name(e: *const Expr) -> *const c_char {
    if e.is_null() {
        return ptr::null();
    }
    let expr = unsafe { (*e).clone() };
    match expr.meta().output_name() {
        Ok(name) => rust_string_to_ptr(&*name),
        Err(_) => ptr::null(),
    }
}

fn root_names(e: *const Expr) -> Vec<Arc<str>> {
    unsafe { (*e).clone() }.meta().root_names()
}

#[no_mangle]
pub extern "C" fn expr_meta_root_names_len(e: *const Expr) -> usize {
    if e.is_null() {
        return 0;
    }
    root_names(e).len()
}

#[no_mangle]
pub extern "C" fn expr_meta_root_name(
    e: *const Expr,
    index: usize,
) -> *const c_char {
    if e.is_null() {
        return ptr::null();
    }
    match root_names(e).get(index) {
        Some(name) => rust_string_to_ptr(&**name),
        None => ptr::null(),
    }
}

#[no_mangle]
pub extern "C" fn expr_meta_eq(a: *const Expr, b: *const Expr) -> u8 {
    if a.is_null() || b.is_null() {
        return 0;
    }
    unsafe { (*a == *b) as u8 }
}
