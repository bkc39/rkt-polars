use super::test_util::*;
use super::*;

fn read_i32(s: *mut Series) -> Vec<i32> {
    (0..series_len(s))
        .map(|i| {
            let v = series_ref_i32(s, i);
            assert_eq!(v.valid, 1);
            v.value
        })
        .collect()
}

fn read_f64(s: *mut Series) -> Vec<f64> {
    (0..series_len(s))
        .map(|i| {
            let v = series_ref_f64(s, i);
            assert_eq!(v.valid, 1);
            v.value
        })
        .collect()
}

#[test]
fn arith_i32_family_against_scalar() {
    let s = make_i32("xs", &[10, 20, 30]);
    let add = series_add_i32(s, 5);
    assert_eq!(read_i32(add), vec![15, 25, 35]);
    series_drop(add);
    let sub = series_sub_i32(s, 5);
    assert_eq!(read_i32(sub), vec![5, 15, 25]);
    series_drop(sub);
    let mul = series_mul_i32(s, 2);
    assert_eq!(read_i32(mul), vec![20, 40, 60]);
    series_drop(mul);
    let div = series_div_i32(s, 5);
    // i32 / i32 stays i32 (integer division).
    assert_eq!(read_i32(div), vec![2, 4, 6]);
    series_drop(div);
    let rem = series_mod_i32(s, 7);
    assert_eq!(read_i32(rem), vec![3, 6, 2]);
    series_drop(rem);
    series_drop(s);
}

#[test]
fn arith_f64_family_against_scalar() {
    let s = make_f64("ys", &[1.0, 2.0, 4.0]);
    let add = series_add_f64(s, 0.5);
    assert_eq!(read_f64(add), vec![1.5, 2.5, 4.5]);
    series_drop(add);
    let div = series_div_f64(s, 4.0);
    assert_eq!(read_f64(div), vec![0.25, 0.5, 1.0]);
    series_drop(div);
    series_drop(s);
}

#[test]
fn arith_i64_add_smoke() {
    let s = make_i64("ys", &[1, 2, 3]);
    let add = series_add_i64(s, 10);
    let v0 = series_ref_i64(add, 0);
    assert_eq!(v0.valid, 1);
    assert_eq!(v0.value, 11);
    assert_eq!(series_ref_i64(add, 2).value, 13);
    series_drop(add);
    series_drop(s);
}

#[test]
fn arith_u32_mul_smoke() {
    let n = cstr("xs");
    let data: [u32; 3] = [1, 2, 3];
    let s = series_new_u32(n.as_ptr(), data.as_ptr(), data.len());
    let mul = series_mul_u32(s, 4);
    assert_eq!(series_ref_u32(mul, 0).value, 4);
    assert_eq!(series_ref_u32(mul, 2).value, 12);
    series_drop(mul);
    series_drop(s);
}

const ARITH_SCALAR_OPS: &[ScalarRow] = scalar_ops![
    "Int32" 1: [
        series_add_i32, series_sub_i32, series_mul_i32, series_div_i32,
        series_mod_i32,
    ],
    "Int64" 1: [
        series_add_i64, series_sub_i64, series_mul_i64, series_div_i64,
        series_mod_i64,
    ],
    "UInt32" 1: [
        series_add_u32, series_sub_u32, series_mul_u32, series_div_u32,
        series_mod_u32,
    ],
    "UInt64" 1: [
        series_add_u64, series_sub_u64, series_mul_u64, series_div_u64,
        series_mod_u64,
    ],
    "Float64" 1.0: [
        series_add_f64, series_sub_f64, series_mul_f64, series_div_f64,
        series_mod_f64,
    ],
];

const BY_ZERO: &[ScalarRow] = scalar_ops![
    "Int32" 0: [series_div_i32, series_mod_i32],
    "Int64" 0: [series_div_i64, series_mod_i64],
    "UInt32" 0: [series_div_u32, series_mod_u32],
    "UInt64" 0: [series_div_u64, series_mod_u64],
];

#[test]
fn the_arith_table_holds_every_operator() {
    assert_eq!(ARITH_SCALAR_OPS.len(), 25);
}

#[test]
fn arith_scalar_ops_clear_a_stale_reason() {
    assert_ops_clear_a_stale_reason(ARITH_SCALAR_OPS);
}

#[test]
fn arith_scalar_ops_report_the_wrong_dtype() {
    assert_ops_report_the_wrong_dtype(ARITH_SCALAR_OPS);
}

#[test]
fn arith_scalar_null_series_reports_it() {
    assert_ops_report_a_null_series(ARITH_SCALAR_OPS);
}

#[test]
fn integer_division_by_zero_is_null_and_no_failure() {
    for &(name, op, dtype) in BY_ZERO {
        let s = make_of(dtype, "xs");
        set_last_error("stale");
        let out = op(s);
        assert!(!out.is_null(), "{}", name);
        assert_eq!(recorded_error(), None, "{}", name);
        assert_eq!(series_null_count(out), series_len(out), "{}", name);
        series_drop(out);
        series_drop(s);
    }
}

#[test]
fn signed_minimum_by_minus_one_and_no_failure() {
    let s = make_i32("xs", &[i32::MIN, 7]);
    set_last_error("stale");
    let div = series_div_i32(s, -1);
    let rem = series_mod_i32(s, -1);
    assert_eq!(recorded_error(), None);
    assert_eq!(opt_i32s(div), vec![Some(i32::MIN), Some(-7)]);
    assert_eq!(opt_i32s(rem), vec![Some(0), Some(0)]);
    series_drop(div);
    series_drop(rem);
    series_drop(s);
    let s = make_i64("ys", &[i64::MIN, 7]);
    let div = series_div_i64(s, -1);
    let rem = series_mod_i64(s, -1);
    assert_eq!(recorded_error(), None);
    let read = |p: *mut Series| -> Vec<i64> {
        (0..series_len(p))
            .map(|i| series_ref_i64(p, i).value)
            .collect()
    };
    assert_eq!(read(div), vec![i64::MIN, -7]);
    assert_eq!(read(rem), vec![0, 0]);
    series_drop(div);
    series_drop(rem);
    series_drop(s);
}
