use super::test_util::*;
use super::*;

#[test]
fn cmp_i32_all_ops_against_scalar() {
    let s = make_i32("xs", &[1, 2, 3, 4]);
    let lt = series_lt_i32(s, 3);
    assert_eq!(read_bool_series(lt), vec![true, true, false, false]);
    series_drop(lt);
    let le = series_le_i32(s, 3);
    assert_eq!(read_bool_series(le), vec![true, true, true, false]);
    series_drop(le);
    let gt = series_gt_i32(s, 3);
    assert_eq!(read_bool_series(gt), vec![false, false, false, true]);
    series_drop(gt);
    let ge = series_ge_i32(s, 3);
    assert_eq!(read_bool_series(ge), vec![false, false, true, true]);
    series_drop(ge);
    let eq = series_eq_i32(s, 3);
    assert_eq!(read_bool_series(eq), vec![false, false, true, false]);
    series_drop(eq);
    let ne = series_ne_i32(s, 3);
    assert_eq!(read_bool_series(ne), vec![true, true, false, true]);
    series_drop(ne);
    series_drop(s);
}

#[test]
fn cmp_f64_all_ops_against_scalar() {
    let s = make_f64("ys", &[1.5, 2.5, 3.5]);
    let lt = series_lt_f64(s, 2.5);
    assert_eq!(read_bool_series(lt), vec![true, false, false]);
    series_drop(lt);
    let eq = series_eq_f64(s, 2.5);
    assert_eq!(read_bool_series(eq), vec![false, true, false]);
    series_drop(eq);
    let ge = series_ge_f64(s, 2.5);
    assert_eq!(read_bool_series(ge), vec![false, true, true]);
    series_drop(ge);
    series_drop(s);
}

#[test]
fn cmp_str_eq_and_ne() {
    let s = make_str("ws", &["a", "b", "a"]);
    let rhs = cstr("a");
    let eq = series_eq_str(s, rhs.as_ptr());
    assert_eq!(read_bool_series(eq), vec![true, false, true]);
    series_drop(eq);
    let ne = series_ne_str(s, rhs.as_ptr());
    assert_eq!(read_bool_series(ne), vec![false, true, false]);
    series_drop(ne);
    series_drop(s);
}

#[test]
fn cmp_scalar_null_series_returns_null() {
    assert!(series_lt_i32(ptr::null_mut(), 0).is_null());
    assert!(series_eq_f64(ptr::null_mut(), 0.0).is_null());
    let rhs = cstr("a");
    assert!(series_eq_str(ptr::null_mut(), rhs.as_ptr()).is_null());
}

#[test]
fn cmp_str_null_rhs_returns_null() {
    let s = make_str("ws", &["a"]);
    assert!(series_eq_str(s, ptr::null()).is_null());
    series_drop(s);
}
