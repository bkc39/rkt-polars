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

const UNPACK_I32: &str =
    "invalid series dtype: expected `Boolean`, got `i32` for series with name `i`";

#[test]
fn logical_ops_record_why_they_refuse() {
    let ints = make_i32("i", &[1, 2]);
    let bools = make_bool("b", &[1, 0]);
    let long = make_bool("l", &[1, 0, 1]);
    for out in [series_and(ints, bools), series_or(bools, ints)] {
        assert!(out.is_null());
        assert_eq!(recorded_error().as_deref(), Some(UNPACK_I32));
    }
    assert!(series_not(ints).is_null());
    assert_eq!(recorded_error().as_deref(), Some(UNPACK_I32));
    assert!(series_xor(bools, long).is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("cannot combine series of different lengths: got 2 and 3")
    );
    let ok = series_and(bools, bools);
    assert!(!ok.is_null());
    assert_eq!(recorded_error(), None);
    for s in [ok, ints, bools, long] {
        series_drop(s);
    }
}
