use super::test_util;
use super::*;

mod core;

/// Build a tiny grouped DataFrame: `g` = ["a","a","b","b","b"],
/// `x` = [10,20,30,40,50]. Returned with the input Series so the
/// caller can drop everything cleanly.
fn make_gx() -> (*mut DataFrame, *mut Series, *mut Series) {
    let gs = test_util::make_str("g", &["a", "a", "b", "b", "b"]);
    let xs = test_util::make_i32("x", &[10, 20, 30, 40, 50]);
    let df = test_util::make_df(&[gs, xs]);
    (df, gs, xs)
}

mod asof;
mod groupby;
mod io;
mod join;
mod reshape;
mod smoke;
mod stack;
