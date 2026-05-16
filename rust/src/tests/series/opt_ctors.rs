use super::test_util::*;
use super::*;

#[test]
fn opt_i32_mixed_valid_round_trips() {
    let s = make_opt_i32("xs", &[Some(10), None, Some(30), None]);
    assert_eq!(series_len(s), 4);
    assert_eq!(series_null_count(s), 2);
    assert_eq!(
        series_ref_i32(s, 0),
        CompatOptI32 {
            valid: 1,
            value: 10
        }
    );
    assert_eq!(series_ref_i32(s, 1), CompatOptI32 { valid: 0, value: 0 });
    assert_eq!(
        series_ref_i32(s, 2),
        CompatOptI32 {
            valid: 1,
            value: 30
        }
    );
    assert_eq!(series_ref_i32(s, 3), CompatOptI32 { valid: 0, value: 0 });
    series_drop(s);
}

#[test]
fn opt_f64_mixed_valid_round_trips() {
    let s = make_opt_f64("ys", &[Some(1.5), None, Some(-2.25)]);
    assert_eq!(series_null_count(s), 1);
    let v0 = series_ref_f64(s, 0);
    assert_eq!(v0.valid, 1);
    assert_eq!(v0.value, 1.5);
    let v1 = series_ref_f64(s, 1);
    assert_eq!(v1.valid, 0);
    let v2 = series_ref_f64(s, 2);
    assert_eq!(v2.valid, 1);
    assert_eq!(v2.value, -2.25);
    series_drop(s);
}

#[test]
fn opt_str_mixed_valid_round_trips() {
    // series_new_opt_str: parallel data + valid arrays. NULL
    // entries in the data slot are tolerated when valid=0.
    let owned = [cstr("hi"), cstr("there")];
    let data = [owned[0].as_ptr(), ptr::null(), owned[1].as_ptr()];
    let valid = [1u8, 0, 1];
    let n = cstr("ws");
    let s = series_new_opt_str(
        n.as_ptr(),
        data.as_ptr(),
        valid.as_ptr(),
        data.len(),
    );
    assert!(!s.is_null());
    assert_eq!(series_null_count(s), 1);
    assert_eq!(take_cstring(series_ref_str(s, 0)), "hi");
    assert!(series_ref_str(s, 1).is_null());
    assert_eq!(take_cstring(series_ref_str(s, 2)), "there");
    series_drop(s);
}

#[test]
fn opt_bool_mixed_valid_round_trips() {
    let n = cstr("flags");
    let data: [u8; 3] = [1, 0, 1];
    let valid: [u8; 3] = [1, 0, 1];
    let s = series_new_opt_bool(
        n.as_ptr(),
        data.as_ptr(),
        valid.as_ptr(),
        data.len(),
    );
    assert!(!s.is_null());
    assert_eq!(series_null_count(s), 1);
    assert_eq!(series_ref_bool(s, 0).valid, 1);
    assert_eq!(series_ref_bool(s, 0).value, 1);
    assert_eq!(series_ref_bool(s, 1).valid, 0);
    assert_eq!(series_ref_bool(s, 2).value, 1);
    series_drop(s);
}

#[test]
fn opt_i32_empty_ok() {
    let n = cstr("xs");
    let s = series_new_opt_i32(n.as_ptr(), ptr::null(), ptr::null(), 0);
    assert!(!s.is_null());
    assert_eq!(series_len(s), 0);
    series_drop(s);
}

#[test]
fn opt_i64_null_name_returns_null() {
    let data: [i64; 1] = [1];
    let valid: [u8; 1] = [1];
    let s = series_new_opt_i64(ptr::null(), data.as_ptr(), valid.as_ptr(), 1);
    assert!(s.is_null());
}

#[test]
fn opt_ymdhms_mixed_valid_round_trips() {
    let n = cstr("ts");
    let data = [
        YMDHMS {
            year: 2024,
            month: 1,
            day: 2,
            hour: 3,
            minute: 4,
            second: 5,
        },
        YMDHMS {
            year: 0,
            month: 0,
            day: 0,
            hour: 0,
            minute: 0,
            second: 0,
        },
    ];
    let valid = [1u8, 0];
    let s = series_new_opt_ymdhms(
        n.as_ptr(),
        data.as_ptr(),
        valid.as_ptr(),
        data.len(),
    );
    assert!(!s.is_null());
    assert_eq!(series_null_count(s), 1);
    let v0 = series_ref_ymdhms(s, 0);
    assert_eq!(v0.valid, 1);
    assert_eq!(v0.value.year, 2024);
    assert_eq!(v0.value.month, 1);
    assert_eq!(v0.value.hour, 3);
    let v1 = series_ref_ymdhms(s, 1);
    assert_eq!(v1.valid, 0);
    series_drop(s);
}
