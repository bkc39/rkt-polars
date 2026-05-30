use super::test_util::*;
use super::*;

macro_rules! ctor_happy_path {
    ($name:ident, $build:expr, $tag:ident) => {
        #[test]
        fn $name() {
            let s = $build;
            assert_eq!(series_len(s), 4);
            assert_dtype(s, CompatDTypeTag::$tag, CompatTimeUnit::None);
            series_drop(s);
        }
    };
}

ctor_happy_path!(
    ctor_i8,
    {
        let n = cstr("xs");
        let data: [i8; 4] = [-1, 0, 1, 2];
        series_new_i8(n.as_ptr(), data.as_ptr(), data.len())
    },
    Int8
);
ctor_happy_path!(
    ctor_i16,
    {
        let n = cstr("xs");
        let data: [i16; 4] = [-1, 0, 1, 2];
        series_new_i16(n.as_ptr(), data.as_ptr(), data.len())
    },
    Int16
);
ctor_happy_path!(ctor_i64, make_i64("xs", &[-1, 0, 1, 2]), Int64);
ctor_happy_path!(
    ctor_u8,
    {
        let n = cstr("xs");
        let data: [u8; 4] = [0, 1, 2, 3];
        series_new_u8(n.as_ptr(), data.as_ptr(), data.len())
    },
    UInt8
);
ctor_happy_path!(
    ctor_u16,
    {
        let n = cstr("xs");
        let data: [u16; 4] = [0, 1, 2, 3];
        series_new_u16(n.as_ptr(), data.as_ptr(), data.len())
    },
    UInt16
);
ctor_happy_path!(
    ctor_u32,
    {
        let n = cstr("xs");
        let data: [u32; 4] = [0, 1, 2, 3];
        series_new_u32(n.as_ptr(), data.as_ptr(), data.len())
    },
    UInt32
);
ctor_happy_path!(
    ctor_u64,
    {
        let n = cstr("xs");
        let data: [u64; 4] = [0, 1, 2, 3];
        series_new_u64(n.as_ptr(), data.as_ptr(), data.len())
    },
    UInt64
);
ctor_happy_path!(
    ctor_f32,
    {
        let n = cstr("xs");
        let data: [f32; 4] = [0.0, 1.5, -2.5, 3.0];
        series_new_f32(n.as_ptr(), data.as_ptr(), data.len())
    },
    Float32
);
ctor_happy_path!(ctor_bool, make_bool("flags", &[1, 0, 1, 0]), Boolean);

#[test]
fn ctor_i64_null_name_returns_null() {
    let data: [i64; 1] = [42];
    let s = series_new_i64(ptr::null(), data.as_ptr(), data.len());
    assert!(s.is_null(), "null name must produce null Series");
}

#[test]
fn ctor_u32_null_data_returns_null() {
    let n = cstr("xs");
    let s = series_new_u32(n.as_ptr(), ptr::null(), 4);
    assert!(s.is_null(), "null data + nonzero length must reject");
}

#[test]
fn ctor_bool_null_name_returns_null() {
    let data: [u8; 1] = [1];
    let s = series_new_bool(ptr::null(), data.as_ptr(), data.len());
    assert!(s.is_null());
}

#[test]
fn ctor_bool_empty_ok() {
    // Empty bool series is allowed: data may be null when length=0.
    let n = cstr("flags");
    let s = series_new_bool(n.as_ptr(), ptr::null(), 0);
    assert!(!s.is_null());
    assert_eq!(series_len(s), 0);
    series_drop(s);
}

#[test]
fn ctor_ymdhms_happy_path() {
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
            year: 2025,
            month: 6,
            day: 7,
            hour: 8,
            minute: 9,
            second: 10,
        },
    ];
    let s = series_new_ymdhms(n.as_ptr(), data.as_ptr(), data.len());
    assert!(!s.is_null());
    assert_eq!(series_len(s), 2);
    assert_dtype(s, CompatDTypeTag::Datetime, CompatTimeUnit::Milliseconds);
    series_drop(s);
}
