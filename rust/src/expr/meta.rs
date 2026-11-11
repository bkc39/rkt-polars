use crate::prelude::*;
use crate::{
    deref_arg, scalar_result, str_list_out, str_out, without_floors,
    StrListOut, StrOut,
};

#[no_mangle]
pub extern "C" fn expr_meta_output_name_v2(e: *const Expr) -> StrOut {
    scalar_result(ptr::null_mut(), || {
        let expr = unsafe { deref_arg(e, "expression") }?;
        expr.clone().meta().output_name().map(|name| str_out(&name))
    })
}

#[no_mangle]
pub extern "C" fn expr_meta_root_names(e: *const Expr) -> StrListOut {
    unsafe { e.as_ref() }.map_or(ptr::null_mut(), |expr| {
        str_list_out(without_floors(expr.clone()).meta().root_names())
    })
}

#[no_mangle]
pub extern "C" fn expr_meta_eq(a: *const Expr, b: *const Expr) -> u8 {
    if a.is_null() || b.is_null() {
        return 0;
    }
    unsafe { (*a == *b) as u8 }
}
