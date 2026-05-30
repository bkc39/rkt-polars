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

#[test]
fn arith_scalar_null_series_returns_null() {
    assert!(series_add_i32(ptr::null_mut(), 1).is_null());
    assert!(series_div_f64(ptr::null_mut(), 1.0).is_null());
}
