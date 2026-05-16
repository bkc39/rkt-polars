use super::test_util::*;
use super::*;

#[test]
fn ref_i32_happy_path() {
    let s = make_i32("xs", &[10, 20, 30]);
    assert_eq!(series_ref_i32(s, 0).value, 10);
    assert_eq!(series_ref_i32(s, 2).value, 30);
    series_drop(s);
}

#[test]
fn ref_i32_null_series_returns_none() {
    let v = series_ref_i32(ptr::null_mut(), 0);
    assert_eq!(v, CompatOptI32 { valid: 0, value: 0 });
}

#[test]
fn ref_f64_returns_value() {
    let s = make_f64("ys", &[1.5, 2.5, 3.5]);
    assert_eq!(series_ref_f64(s, 1).value, 2.5);
    series_drop(s);
}

#[test]
fn ref_str_returns_cstring_and_frees() {
    let s = make_str("ws", &["hi", "there"]);
    let p0 = series_ref_str(s, 0);
    assert!(!p0.is_null());
    assert_eq!(take_cstring(p0), "hi");
    assert_eq!(take_cstring(series_ref_str(s, 1)), "there");
    series_drop(s);
}

#[test]
fn ref_str_null_series_returns_null_ptr() {
    assert!(series_ref_str(ptr::null_mut(), 0).is_null());
}

#[test]
fn ref_bool_returns_value() {
    let s = make_bool("flags", &[1, 0, 1]);
    assert_eq!(series_ref_bool(s, 0).value, 1);
    assert_eq!(series_ref_bool(s, 1).value, 0);
    series_drop(s);
}

#[test]
fn ref_is_null_flags_null_entries() {
    let s = make_opt_i32("xs", &[Some(1), None, Some(3)]);
    assert_eq!(series_ref_is_null(s, 0), 0);
    assert_eq!(series_ref_is_null(s, 1), 1);
    assert_eq!(series_ref_is_null(s, 2), 0);
    // out-of-range → -1
    assert_eq!(series_ref_is_null(s, 99), -1);
    // null series → -1
    assert_eq!(series_ref_is_null(ptr::null_mut(), 0), -1);
    series_drop(s);
}

#[test]
fn ref_date_returns_ymd() {
    // Build an i32 series of epoch-days then cast → Date.
    let raw = make_i32("d", &[0, 1, 365]);
    let target = CompatDType {
        tag: CompatDTypeTag::Date as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    };
    let dates = series_cast(raw, target);
    assert!(!dates.is_null());
    assert_dtype(dates, CompatDTypeTag::Date, CompatTimeUnit::None);
    let v0 = series_ref_date(dates, 0);
    assert_eq!(v0.valid, 1);
    assert_eq!(v0.value.year, 1970);
    assert_eq!(v0.value.month, 1);
    assert_eq!(v0.value.day, 1);
    let v2 = series_ref_date(dates, 2);
    assert_eq!(v2.valid, 1);
    assert_eq!(v2.value.year, 1971);
    assert_eq!(v2.value.month, 1);
    assert_eq!(v2.value.day, 1);
    series_drop(raw);
    series_drop(dates);
}

#[test]
fn ref_duration_returns_i64() {
    let raw = make_i64("d", &[0, 1_000, 60_000]);
    let target = CompatDType {
        tag: CompatDTypeTag::Duration as i32,
        time_unit: CompatTimeUnit::Milliseconds as i32,
        flags: 0,
        array_width: 0,
    };
    let durs = series_cast(raw, target);
    assert!(!durs.is_null());
    assert_dtype(durs, CompatDTypeTag::Duration, CompatTimeUnit::Milliseconds);
    assert_eq!(series_ref_duration(durs, 1).value, 1_000);
    assert_eq!(series_ref_duration(durs, 2).value, 60_000);
    series_drop(raw);
    series_drop(durs);
}

#[test]
fn ref_time_returns_i64() {
    // Polars Time stores nanoseconds-since-midnight as i64.
    let raw = make_i64("t", &[0, 1_000_000_000]);
    let target = CompatDType {
        tag: CompatDTypeTag::Time as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    };
    let times = series_cast(raw, target);
    assert!(!times.is_null());
    assert_dtype(times, CompatDTypeTag::Time, CompatTimeUnit::None);
    assert_eq!(series_ref_time(times, 0).value, 0);
    assert_eq!(series_ref_time(times, 1).value, 1_000_000_000);
    series_drop(raw);
    series_drop(times);
}

#[test]
fn ref_ymdhms_returns_value() {
    let n = cstr("ts");
    let data = [YMDHMS {
        year: 2030,
        month: 11,
        day: 22,
        hour: 13,
        minute: 14,
        second: 15,
    }];
    let s = series_new_ymdhms(n.as_ptr(), data.as_ptr(), data.len());
    let v = series_ref_ymdhms(s, 0);
    assert_eq!(v.valid, 1);
    assert_eq!(v.value.year, 2030);
    assert_eq!(v.value.month, 11);
    assert_eq!(v.value.day, 22);
    assert_eq!(v.value.hour, 13);
    assert_eq!(v.value.minute, 14);
    assert_eq!(v.value.second, 15);
    series_drop(s);
}
