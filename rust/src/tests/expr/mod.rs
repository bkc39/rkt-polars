use super::test_util;
use super::*;

mod core;
mod meta;
mod selectors;

fn column(name: &str) -> *mut Expr {
    let n = test_util::cstr(name);
    let e = expr_col(n.as_ptr());
    assert!(!e.is_null(), "expr_col returned null for {:?}", name);
    e
}

fn aliased(e: *const Expr, name: &str) -> *mut Expr {
    let n = test_util::cstr(name);
    let out = expr_alias(e, n.as_ptr());
    assert!(!out.is_null(), "expr_alias returned null for {:?}", name);
    out
}
