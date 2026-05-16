use super::test_util::*;
use super::*;

#[test]
fn dtype_each_int_width() {
    let cases: &[(*mut Series, CompatDTypeTag)] = &[
        (make_i32("a", &[1]), CompatDTypeTag::Int32),
        (make_i64("a", &[1]), CompatDTypeTag::Int64),
    ];
    for (s, tag) in cases {
        assert_dtype(*s, *tag, CompatTimeUnit::None);
        series_drop(*s);
    }
}

#[test]
fn dtype_each_float_width() {
    let s64 = make_f64("a", &[1.0]);
    assert_dtype(s64, CompatDTypeTag::Float64, CompatTimeUnit::None);
    series_drop(s64);

    // f32 needs a direct ctor call since no test_util helper exists.
    let n = cstr("a");
    let data: [f32; 1] = [1.0];
    let s32 = series_new_f32(n.as_ptr(), data.as_ptr(), data.len());
    assert_dtype(s32, CompatDTypeTag::Float32, CompatTimeUnit::None);
    series_drop(s32);
}

#[test]
fn dtype_bool_and_string() {
    let b = make_bool("b", &[1, 0]);
    assert_dtype(b, CompatDTypeTag::Boolean, CompatTimeUnit::None);
    series_drop(b);
    let s = make_str("s", &["x"]);
    assert_dtype(s, CompatDTypeTag::String, CompatTimeUnit::None);
    series_drop(s);
}
