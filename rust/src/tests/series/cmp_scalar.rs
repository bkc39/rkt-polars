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

const CMP_SCALAR_OPS: &[ScalarRow] = scalar_ops![
    "Int32" 1: [
        series_lt_i32, series_le_i32, series_gt_i32, series_ge_i32,
        series_eq_i32, series_ne_i32,
    ],
    "Float64" 1.0: [
        series_lt_f64, series_le_f64, series_gt_f64, series_ge_f64,
        series_eq_f64, series_ne_f64,
    ],
];

#[test]
fn the_cmp_table_holds_every_operator() {
    assert_eq!(CMP_SCALAR_OPS.len(), 12);
}

#[test]
fn cmp_scalar_ops_clear_a_stale_reason() {
    assert_ops_clear_a_stale_reason(CMP_SCALAR_OPS);
}

#[test]
fn cmp_scalar_ops_report_the_wrong_dtype() {
    assert_ops_report_the_wrong_dtype(CMP_SCALAR_OPS);
}

#[test]
fn cmp_scalar_null_series_reports_it() {
    assert_ops_report_a_null_series(CMP_SCALAR_OPS);
}
