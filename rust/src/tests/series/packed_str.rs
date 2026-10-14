use super::test_util::*;
use super::*;

fn packed(
    name: *const c_char,
    buf: &[u8],
    offsets: &[i64],
    valid: Option<&[u8]>,
) -> *mut Series {
    series_new_str_packed(
        name,
        buf.as_ptr(),
        buf.len(),
        offsets.as_ptr(),
        offsets.len(),
        valid.map_or(ptr::null(), <[u8]>::as_ptr),
        valid.map_or(0, <[u8]>::len),
    )
}

fn values(s: *mut Series) -> Vec<Option<String>> {
    let series = unsafe { &*s };
    series
        .str()
        .unwrap()
        .iter()
        .map(|value| value.map(str::to_owned))
        .collect()
}

#[test]
fn packed_rows_round_trip_with_nulls_and_non_ascii() {
    let rows = [
        Some("héllo"),
        None,
        Some(""),
        Some("a\0b"),
        Some("a string longer than twelve bytes, so not inline 😀"),
        None,
        Some("東京"),
    ];
    let s = make_opt_str("words", &rows);
    assert_eq!(take_cstring(series_name(s)), "words");
    assert_dtype(s, CompatDTypeTag::String, CompatTimeUnit::None);
    assert_eq!(series_null_count(s), 2);
    let expected: Vec<Option<String>> =
        rows.iter().map(|v| v.map(str::to_owned)).collect();
    assert_eq!(values(s), expected);
    series_drop(s);
}

#[test]
fn packed_without_validity_has_no_nulls() {
    let n = cstr("xs");
    let s = packed(n.as_ptr(), b"onetwothree", &[0, 3, 6, 11], None);
    assert!(!s.is_null());
    assert_eq!(series_null_count(s), 0);
    assert_eq!(
        values(s),
        [Some("one".into()), Some("two".into()), Some("three".into())]
    );
    series_drop(s);
}

#[test]
fn packed_null_name_is_empty() {
    let s = packed(ptr::null(), b"ab", &[0, 1, 2], None);
    assert!(!s.is_null());
    assert_eq!(take_cstring(series_name(s)), "");
    series_drop(s);
}

#[test]
fn packed_many_rows() {
    let owned: Vec<String> = (0..200_000).map(|i| format!("r{i}é")).collect();
    let rows: Vec<Option<&str>> = owned
        .iter()
        .enumerate()
        .map(|(i, v)| (i % 7 != 3).then_some(v.as_str()))
        .collect();
    let s = make_opt_str("many", &rows);
    let expected: Vec<Option<String>> =
        rows.iter().map(|v| v.map(str::to_owned)).collect();
    assert_eq!(values(s), expected);
    series_drop(s);
}

#[test]
fn packed_refusals_return_null() {
    let n = cstr("xs");
    let name = n.as_ptr();
    let good_valid = [1u8, 1];
    let cases: [(&str, &[u8], &[i64], Option<&[u8]>); 9] = [
        ("zero rows", b"", &[0], None),
        ("no offsets", b"", &[], None),
        ("decreasing offsets", b"abc", &[0, 2, 1], None),
        ("negative offset", b"abc", &[-1, 1, 2], None),
        ("offset past the buffer", b"abc", &[0, 1, 4], None),
        (
            "offset inside a character",
            "é".as_bytes(),
            &[0, 1, 2],
            None,
        ),
        ("invalid UTF-8", &[0xff, 0x61], &[0, 1, 2], None),
        ("short validity", b"ab", &[0, 1, 2], Some(&good_valid[..1])),
        ("first offset past the buffer", b"ab", &[3, 3, 3], None),
    ];
    for (why, buf, offsets, valid) in cases {
        set_last_error("stale");
        assert!(packed(name, buf, offsets, valid).is_null(), "{why}");
        assert_eq!(recorded_error(), None, "{why}");
    }
    assert!(!packed(name, b"ab", &[0, 1, 2], Some(&good_valid)).is_null());
}

#[test]
fn packed_refuses_null_pointers() {
    let n = cstr("xs");
    let offsets = [0i64, 1, 2];
    let buf = b"ab";
    assert!(series_new_str_packed(
        n.as_ptr(),
        ptr::null(),
        2,
        offsets.as_ptr(),
        3,
        ptr::null(),
        0
    )
    .is_null());
    assert!(series_new_str_packed(
        n.as_ptr(),
        buf.as_ptr(),
        2,
        ptr::null(),
        3,
        ptr::null(),
        0
    )
    .is_null());
    let empty = [0i64, 0];
    let s = series_new_str_packed(
        n.as_ptr(),
        ptr::null(),
        0,
        empty.as_ptr(),
        2,
        ptr::null(),
        0,
    );
    assert!(!s.is_null(), "an empty buffer may be NULL");
    assert_eq!(values(s), [Some(String::new())]);
    series_drop(s);
}
