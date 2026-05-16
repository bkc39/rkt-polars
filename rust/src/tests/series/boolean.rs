use super::test_util::*;
use super::*;

#[test]
fn and_or_xor_against_series() {
    let a = make_bool("a", &[1, 1, 0, 0]);
    let b = make_bool("b", &[1, 0, 1, 0]);
    let and = series_and(a, b);
    assert_eq!(read_bool_series(and), vec![true, false, false, false]);
    series_drop(and);
    let or = series_or(a, b);
    assert_eq!(read_bool_series(or), vec![true, true, true, false]);
    series_drop(or);
    let xor = series_xor(a, b);
    assert_eq!(read_bool_series(xor), vec![false, true, true, false]);
    series_drop(xor);
    series_drop(a);
    series_drop(b);
}

#[test]
fn not_inverts_bool_series() {
    let a = make_bool("a", &[1, 0, 1]);
    let nb = series_not(a);
    assert_eq!(read_bool_series(nb), vec![false, true, false]);
    series_drop(nb);
    series_drop(a);
}

#[test]
fn is_null_and_is_not_null_on_nullable_series() {
    let s = make_opt_i32("xs", &[Some(1), None, Some(3)]);
    let isn = series_is_null(s);
    assert_eq!(read_bool_series(isn), vec![false, true, false]);
    series_drop(isn);
    let notn = series_is_not_null(s);
    assert_eq!(read_bool_series(notn), vec![true, false, true]);
    series_drop(notn);
    series_drop(s);
}

#[test]
fn boolean_ops_null_inputs_return_null() {
    let a = make_bool("a", &[1]);
    assert!(series_and(ptr::null_mut(), a).is_null());
    assert!(series_and(a, ptr::null_mut()).is_null());
    assert!(series_not(ptr::null_mut()).is_null());
    assert!(series_is_null(ptr::null_mut()).is_null());
    assert!(series_is_not_null(ptr::null_mut()).is_null());
    series_drop(a);
}
