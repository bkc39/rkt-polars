use super::test_util::*;
use super::*;

#[test]
fn make_i32_builds_named_series() {
    let s = make_i32("xs", &[1, 2, 3, 4]);
    let n = take_cstring(series_name(s));
    assert_eq!(n, "xs");
    assert_eq!(series_len(s), 4);
    assert_dtype(s, CompatDTypeTag::Int32, CompatTimeUnit::None);
    series_drop(s);
}

#[test]
fn make_f64_builds_named_series() {
    let s = make_f64("ys", &[1.5, 2.5]);
    assert_eq!(series_len(s), 2);
    assert_dtype(s, CompatDTypeTag::Float64, CompatTimeUnit::None);
    series_drop(s);
}

#[test]
fn make_bool_builds_named_series() {
    let s = make_bool("flags", &[1u8, 0, 1]);
    assert_eq!(series_len(s), 3);
    assert_dtype(s, CompatDTypeTag::Boolean, CompatTimeUnit::None);
    series_drop(s);
}

#[test]
fn make_str_builds_named_series() {
    let s = make_str("words", &["a", "bb", "ccc"]);
    assert_eq!(series_len(s), 3);
    assert_dtype(s, CompatDTypeTag::String, CompatTimeUnit::None);
    series_drop(s);
}
