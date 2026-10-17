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

#[test]
fn series_ops_record_why_they_refuse() {
    let ints = make_i32("i", &[1, 2]);
    let strs = make_str("s", &["a", "b"]);
    let long = make_i32("l", &[1, 2, 3]);
    assert!(series_sub(ints, strs).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("str"), "{}", reason);
    assert!(series_add(ints, long).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("different lengths"), "{}", reason);
    assert!(series_lt(ints, long).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("different length"), "{}", reason);
    let ok = series_eq(ints, ints);
    assert!(!ok.is_null());
    assert_eq!(recorded_error(), None);
    for s in [ok, ints, strs, long] {
        series_drop(s);
    }
}
