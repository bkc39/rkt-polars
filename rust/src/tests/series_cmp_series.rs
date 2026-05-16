use super::test_util::*;
use super::*;

#[test]
fn eq_ne_gt_ge_lt_le_against_series() {
    let a = make_i32("a", &[1, 2, 3, 4]);
    let b = make_i32("b", &[2, 2, 2, 5]);
    let eq = series_eq(a, b);
    assert_eq!(read_bool_series(eq), vec![false, true, false, false]);
    series_drop(eq);
    let ne = series_ne(a, b);
    assert_eq!(read_bool_series(ne), vec![true, false, true, true]);
    series_drop(ne);
    let gt = series_gt(a, b);
    assert_eq!(read_bool_series(gt), vec![false, false, true, false]);
    series_drop(gt);
    let ge = series_ge(a, b);
    assert_eq!(read_bool_series(ge), vec![false, true, true, false]);
    series_drop(ge);
    let lt = series_lt(a, b);
    assert_eq!(read_bool_series(lt), vec![true, false, false, true]);
    series_drop(lt);
    let le = series_le(a, b);
    assert_eq!(read_bool_series(le), vec![true, true, false, true]);
    series_drop(le);
    series_drop(a);
    series_drop(b);
}

#[test]
fn cmp_series_null_inputs_return_null() {
    let s = make_i32("a", &[1]);
    assert!(series_eq(ptr::null_mut(), s).is_null());
    assert!(series_eq(s, ptr::null_mut()).is_null());
    series_drop(s);
}
