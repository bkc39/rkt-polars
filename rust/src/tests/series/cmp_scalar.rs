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

type ScalarOp = fn(*mut Series) -> *mut Series;

const CMP_SCALAR_OPS: [(&str, ScalarOp, &str); 12] = [
    ("series_lt_i32", |s| series_lt_i32(s, 1), "Int32"),
    ("series_le_i32", |s| series_le_i32(s, 1), "Int32"),
    ("series_gt_i32", |s| series_gt_i32(s, 1), "Int32"),
    ("series_ge_i32", |s| series_ge_i32(s, 1), "Int32"),
    ("series_eq_i32", |s| series_eq_i32(s, 1), "Int32"),
    ("series_ne_i32", |s| series_ne_i32(s, 1), "Int32"),
    ("series_lt_f64", |s| series_lt_f64(s, 1.0), "Float64"),
    ("series_le_f64", |s| series_le_f64(s, 1.0), "Float64"),
    ("series_gt_f64", |s| series_gt_f64(s, 1.0), "Float64"),
    ("series_ge_f64", |s| series_ge_f64(s, 1.0), "Float64"),
    ("series_eq_f64", |s| series_eq_f64(s, 1.0), "Float64"),
    ("series_ne_f64", |s| series_ne_f64(s, 1.0), "Float64"),
];

fn make_of(dtype: &str, name: &str) -> *mut Series {
    match dtype {
        "Int32" => make_i32(name, &[3, 4]),
        _ => make_f64(name, &[3.0, 4.0]),
    }
}

#[test]
fn cmp_scalar_ops_clear_a_stale_reason() {
    for (name, op, dtype) in CMP_SCALAR_OPS {
        let s = make_of(dtype, "xs");
        set_last_error("stale");
        let out = op(s);
        assert!(!out.is_null(), "{}", name);
        assert_eq!(recorded_error(), None, "{}", name);
        series_drop(out);
        series_drop(s);
    }
}

#[test]
fn cmp_scalar_ops_report_the_wrong_dtype() {
    for (name, op, dtype) in CMP_SCALAR_OPS {
        let wrong = if dtype == "Int32" { "Float64" } else { "Int32" };
        let s = make_of(wrong, "wrong");
        clear_last_error();
        assert!(op(s).is_null(), "{}", name);
        let reason = recorded_error().unwrap_or_else(|| panic!("{}", name));
        let expected = format!("invalid series dtype: expected `{}`", dtype);
        assert!(reason.contains(&expected), "{}: {}", name, reason);
        assert!(reason.contains("`wrong`"), "{}: {}", name, reason);
        series_drop(s);
    }
}

#[test]
fn cmp_scalar_null_series_reports_it() {
    for (name, op, _) in CMP_SCALAR_OPS {
        clear_last_error();
        assert!(op(ptr::null_mut()).is_null(), "{}", name);
        assert_eq!(
            recorded_error().as_deref(),
            Some("series is null"),
            "{}",
            name
        );
    }
}
