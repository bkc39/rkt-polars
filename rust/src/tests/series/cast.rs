use super::test_util::*;
use super::*;

fn dtype(tag: CompatDTypeTag, tu: CompatTimeUnit) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: tu as i32,
        flags: 0,
        array_width: 0,
    }
}

#[test]
fn cast_i32_to_i64_changes_dtype() {
    let s = make_i32("xs", &[1, 2, 3]);
    let out =
        series_cast(s, dtype(CompatDTypeTag::Int64, CompatTimeUnit::None));
    assert!(!out.is_null());
    assert_dtype(out, CompatDTypeTag::Int64, CompatTimeUnit::None);
    assert_eq!(series_ref_i64(out, 0).value, 1);
    assert_eq!(series_ref_i64(out, 2).value, 3);
    series_drop(out);
    series_drop(s);
}

#[test]
fn cast_f64_to_i32_truncates() {
    let s = make_f64("ys", &[1.7, 2.2, -3.9]);
    let out =
        series_cast(s, dtype(CompatDTypeTag::Int32, CompatTimeUnit::None));
    assert!(!out.is_null());
    assert_dtype(out, CompatDTypeTag::Int32, CompatTimeUnit::None);
    // Polars f64 -> i32 truncates toward zero.
    assert_eq!(series_ref_i32(out, 0).value, 1);
    assert_eq!(series_ref_i32(out, 1).value, 2);
    assert_eq!(series_ref_i32(out, 2).value, -3);
    series_drop(out);
    series_drop(s);
}

#[test]
fn cast_i32_to_string_produces_string_series() {
    let s = make_i32("xs", &[1, 2, 3]);
    let out =
        series_cast(s, dtype(CompatDTypeTag::String, CompatTimeUnit::None));
    assert!(!out.is_null());
    assert_dtype(out, CompatDTypeTag::String, CompatTimeUnit::None);
    assert_eq!(take_cstring(series_ref_str(out, 0)), "1");
    assert_eq!(take_cstring(series_ref_str(out, 2)), "3");
    series_drop(out);
    series_drop(s);
}

#[test]
fn cast_rejected_target_tag_returns_null() {
    // List is accepted on output but not as a cast target, so
    // polars_dtype_from_compat returns None and series_cast must
    // produce a null pointer rather than panic.
    let s = make_i32("xs", &[1]);
    let out = series_cast(s, dtype(CompatDTypeTag::List, CompatTimeUnit::None));
    assert!(out.is_null());
    series_drop(s);
}

#[test]
fn cast_null_series_returns_null() {
    let out = series_cast(
        ptr::null_mut(),
        dtype(CompatDTypeTag::Int64, CompatTimeUnit::None),
    );
    assert!(out.is_null());
}
