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

type ScalarOp = fn(*mut Series) -> *mut Series;

const ARITH_SCALAR_OPS: [(&str, ScalarOp, &str); 25] = [
    ("series_add_i32", |s| series_add_i32(s, 1), "Int32"),
    ("series_sub_i32", |s| series_sub_i32(s, 1), "Int32"),
    ("series_mul_i32", |s| series_mul_i32(s, 1), "Int32"),
    ("series_div_i32", |s| series_div_i32(s, 1), "Int32"),
    ("series_mod_i32", |s| series_mod_i32(s, 1), "Int32"),
    ("series_add_i64", |s| series_add_i64(s, 1), "Int64"),
    ("series_sub_i64", |s| series_sub_i64(s, 1), "Int64"),
    ("series_mul_i64", |s| series_mul_i64(s, 1), "Int64"),
    ("series_div_i64", |s| series_div_i64(s, 1), "Int64"),
    ("series_mod_i64", |s| series_mod_i64(s, 1), "Int64"),
    ("series_add_u32", |s| series_add_u32(s, 1), "UInt32"),
    ("series_sub_u32", |s| series_sub_u32(s, 1), "UInt32"),
    ("series_mul_u32", |s| series_mul_u32(s, 1), "UInt32"),
    ("series_div_u32", |s| series_div_u32(s, 1), "UInt32"),
    ("series_mod_u32", |s| series_mod_u32(s, 1), "UInt32"),
    ("series_add_u64", |s| series_add_u64(s, 1), "UInt64"),
    ("series_sub_u64", |s| series_sub_u64(s, 1), "UInt64"),
    ("series_mul_u64", |s| series_mul_u64(s, 1), "UInt64"),
    ("series_div_u64", |s| series_div_u64(s, 1), "UInt64"),
    ("series_mod_u64", |s| series_mod_u64(s, 1), "UInt64"),
    ("series_add_f64", |s| series_add_f64(s, 1.0), "Float64"),
    ("series_sub_f64", |s| series_sub_f64(s, 1.0), "Float64"),
    ("series_mul_f64", |s| series_mul_f64(s, 1.0), "Float64"),
    ("series_div_f64", |s| series_div_f64(s, 1.0), "Float64"),
    ("series_mod_f64", |s| series_mod_f64(s, 1.0), "Float64"),
];

fn make_of(dtype: &str, name: &str) -> *mut Series {
    let n = cstr(name);
    let s = match dtype {
        "Int32" => series_new_i32(n.as_ptr(), [3i32, 4].as_ptr(), 2),
        "Int64" => series_new_i64(n.as_ptr(), [3i64, 4].as_ptr(), 2),
        "UInt32" => series_new_u32(n.as_ptr(), [3u32, 4].as_ptr(), 2),
        "UInt64" => series_new_u64(n.as_ptr(), [3u64, 4].as_ptr(), 2),
        "Float64" => series_new_f64(n.as_ptr(), [3.0, 4.0].as_ptr(), 2),
        _ => unreachable!("{}", dtype),
    };
    assert!(!s.is_null());
    s
}

#[test]
fn arith_scalar_ops_clear_a_stale_reason() {
    for (name, op, dtype) in ARITH_SCALAR_OPS {
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
fn arith_scalar_ops_report_the_wrong_dtype() {
    for (name, op, dtype) in ARITH_SCALAR_OPS {
        let wrong = if dtype == "Float64" {
            "Int32"
        } else {
            "Float64"
        };
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
fn arith_scalar_null_series_reports_it() {
    for (name, op, _) in ARITH_SCALAR_OPS {
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

#[test]
fn integer_division_by_zero_is_null_and_no_failure() {
    let s = make_i32("xs", &[10, -3]);
    set_last_error("stale");
    let out = series_div_i32(s, 0);
    assert_eq!(opt_i32s(out), vec![None, None]);
    assert_eq!(recorded_error(), None);
    series_drop(out);
    series_drop(s);
}
