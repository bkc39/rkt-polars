use super::*;
use std::ptr;

mod abi;
mod series_constructor_smoke;
mod series_ctors;
mod series_dtype_tag;
mod series_opt_ctors;
mod series_value_access;
mod smoke;
#[path = "util.rs"]
mod test_util;
mod test_util_smoke;

/// Collect the bool entries of a boolean Series (such as a comparison
/// or `is_null` result) into a `Vec<bool>` for compact assertions.
fn read_bool_series(s: *mut Series) -> Vec<bool> {
    let n = series_len(s);
    (0..n)
        .map(|i| {
            let v = series_ref_bool(s, i);
            assert_eq!(v.valid, 1, "unexpected null at index {}", i);
            v.value != 0
        })
        .collect()
}

mod dataframe_core;
mod series_arith_scalar;
mod series_arith_series;
mod series_boolean;
#[path = "series_cast.rs"]
mod series_cast_tests;
mod series_cmp_scalar;
mod series_cmp_series;
mod series_reductions;
mod series_reshaping;

/// Build a tiny grouped DataFrame: `g` = ["a","a","b","b","b"],
/// `x` = [10,20,30,40,50]. Returned with the input Series so the
/// caller can drop everything cleanly.
fn make_gx() -> (*mut DataFrame, *mut Series, *mut Series) {
    let gs = tests::test_util::make_str("g", &["a", "a", "b", "b", "b"]);
    let xs = tests::test_util::make_i32("x", &[10, 20, 30, 40, 50]);
    let df = tests::test_util::make_df(&[gs, xs]);
    (df, gs, xs)
}

mod dataframe_groupby;
mod dataframe_io;
mod dataframe_join;
#[path = "dataframe_asof.rs"]
mod dataframe_join_asof_tests;
mod dataframe_reshape;
mod dataframe_stack;
