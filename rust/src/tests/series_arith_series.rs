use super::test_util::*;
use super::*;

#[test]
fn arith_series_add_i32() {
    let a = make_i32("a", &[1, 2, 3]);
    let b = make_i32("b", &[10, 20, 30]);
    let sum = series_add(a, b);
    let s0 = series_ref_i32(sum, 0);
    assert_eq!(s0.valid, 1);
    assert_eq!(s0.value, 11);
    assert_eq!(series_ref_i32(sum, 2).value, 33);
    series_drop(sum);
    series_drop(a);
    series_drop(b);
}

#[test]
fn arith_series_sub_f64() {
    let a = make_f64("a", &[5.0, 7.0]);
    let b = make_f64("b", &[1.5, 2.5]);
    let diff = series_sub(a, b);
    assert_eq!(series_ref_f64(diff, 0).value, 3.5);
    assert_eq!(series_ref_f64(diff, 1).value, 4.5);
    series_drop(diff);
    series_drop(a);
    series_drop(b);
}

#[test]
fn arith_series_div_f64_keeps_fractions() {
    let a = make_f64("a", &[1.0, 3.0]);
    let b = make_f64("b", &[4.0, 4.0]);
    let q = series_div(a, b);
    assert_eq!(series_ref_f64(q, 0).value, 0.25);
    assert_eq!(series_ref_f64(q, 1).value, 0.75);
    series_drop(q);
    series_drop(a);
    series_drop(b);
}

#[test]
fn arith_series_null_input_returns_null() {
    let a = make_i32("a", &[1]);
    assert!(series_add(ptr::null_mut(), a).is_null());
    assert!(series_add(a, ptr::null_mut()).is_null());
    series_drop(a);
}
