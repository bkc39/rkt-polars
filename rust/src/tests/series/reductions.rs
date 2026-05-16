use super::test_util::*;
use super::*;

#[test]
fn reductions_i32() {
    let s = make_i32("xs", &[1, 2, 3, 4]);
    assert_eq!(series_sum_i32(s).value, 10);
    assert_eq!(series_min_i32(s).value, 1);
    assert_eq!(series_max_i32(s).value, 4);
    assert_eq!(series_mean_i32(s).value, 2.5);
    assert_eq!(series_n_unique(s), 4);
    series_drop(s);
}

#[test]
fn reductions_f64() {
    let s = make_f64("ys", &[1.0, 2.0, 3.0, 4.0]);
    assert_eq!(series_sum_f64(s).value, 10.0);
    assert_eq!(series_min_f64(s).value, 1.0);
    assert_eq!(series_max_f64(s).value, 4.0);
    assert_eq!(series_mean_f64(s).value, 2.5);
    series_drop(s);
}

#[test]
fn reductions_each_int_width_sum() {
    // Hit every typed reduction the series_int_reductions! macro
    // expands to, so a future macro mistake on any width breaks.
    macro_rules! check_sum {
        ($ctor:ident, $sum:ident, $ty:ty, $expected:expr) => {{
            let n = cstr("xs");
            let data: [$ty; 3] = [1, 2, 3];
            let s = $ctor(n.as_ptr(), data.as_ptr(), data.len());
            let v = $sum(s);
            assert_eq!(v.valid, 1);
            assert_eq!(v.value as i64, $expected as i64);
            series_drop(s);
        }};
    }
    check_sum!(series_new_i8, series_sum_i8, i8, 6i64);
    check_sum!(series_new_i16, series_sum_i16, i16, 6i64);
    check_sum!(series_new_i64, series_sum_i64, i64, 6i64);
    check_sum!(series_new_u8, series_sum_u8, u8, 6i64);
    check_sum!(series_new_u16, series_sum_u16, u16, 6i64);
    check_sum!(series_new_u32, series_sum_u32, u32, 6i64);
    check_sum!(series_new_u64, series_sum_u64, u64, 6i64);
}

#[test]
fn reductions_f32() {
    let n = cstr("ys");
    let data: [f32; 4] = [1.0, 2.0, 3.0, 4.0];
    let s = series_new_f32(n.as_ptr(), data.as_ptr(), data.len());
    assert_eq!(series_sum_f32(s).value, 10.0);
    assert_eq!(series_min_f32(s).value, 1.0);
    assert_eq!(series_max_f32(s).value, 4.0);
    assert_eq!(series_mean_f32(s).value, 2.5);
    series_drop(s);
}

#[test]
fn std_var_defaults_to_ddof_1() {
    // [2,4,4,4,5,5,7,9]: sample variance = 32/7 ≈ 4.571.
    let s = make_f64("ys", &[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]);
    let var1 = series_var(s, 1);
    assert_eq!(var1.valid, 1);
    assert!((var1.value - (32.0 / 7.0)).abs() < 1e-9);
    let std1 = series_std(s, 1);
    assert_eq!(std1.valid, 1);
    assert!((std1.value - (32.0 / 7.0_f64).sqrt()).abs() < 1e-9);
    // ddof=0 (population) = 32/8 = 4.0.
    let var0 = series_var(s, 0);
    assert!((var0.value - 4.0).abs() < 1e-9);
    series_drop(s);
}

#[test]
fn n_unique_counts_distinct_entries() {
    let s = make_i32("xs", &[1, 2, 2, 3, 3, 3]);
    assert_eq!(series_n_unique(s), 3);
    series_drop(s);
}

#[test]
fn reductions_all_null_series() {
    // All-null nullable integer series: Polars treats the sum
    // of "nothing" as Some(0), but min / max / mean return
    // None (valid=0).
    let s = make_opt_i32("xs", &[None, None, None]);
    let sum = series_sum_i32(s);
    assert_eq!(sum.valid, 1);
    assert_eq!(sum.value, 0);
    assert_eq!(series_min_i32(s).valid, 0);
    assert_eq!(series_max_i32(s).valid, 0);
    assert_eq!(series_mean_i32(s).valid, 0);
    series_drop(s);
}

#[test]
fn reductions_null_series_return_none() {
    assert_eq!(series_sum_i32(ptr::null_mut()).valid, 0);
    assert_eq!(series_mean_f64(ptr::null_mut()).valid, 0);
    assert_eq!(series_std(ptr::null_mut(), 1).valid, 0);
    assert_eq!(series_var(ptr::null_mut(), 1).valid, 0);
    assert_eq!(series_n_unique(ptr::null_mut()), 0);
}
