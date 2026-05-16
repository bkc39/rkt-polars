use super::test_util;
use super::*;

mod constructor_smoke;
mod ctors;
mod dtype_tag;
mod opt_ctors;
mod smoke;
mod value_access;

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

mod arith_scalar;
mod arith_series;
mod boolean;
mod cast;
mod cmp_scalar;
mod cmp_series;
mod reductions;
mod reshaping;
