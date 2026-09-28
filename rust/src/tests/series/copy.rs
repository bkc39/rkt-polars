use super::*;

fn boxed(s: Series) -> *mut Series {
    Box::into_raw(Box::new(s))
}

fn two_chunks(s: Series) -> Series {
    let mid = s.len() / 2;
    let mut out = s.slice(0, mid);
    out.append(&s.slice(mid as i64, s.len() - mid)).unwrap();
    assert_eq!(out.n_chunks(), 2);
    out
}

fn with_nulls<T: Copy>(values: &[T]) -> Vec<Option<T>> {
    values
        .iter()
        .enumerate()
        .map(|(i, v)| (i % 4 != 1).then_some(*v))
        .collect()
}

fn ranges(n: usize) -> [(usize, usize); 4] {
    [(0, n), (3, n.min(12) - 3), (n - 2, 2), (n, 0)]
}

fn variants(s: Series) -> [Series; 2] {
    let chunked = two_chunks(s);
    let sliced = chunked.slice(3, 9);
    [chunked, sliced]
}

macro_rules! check_physical {
    ($copy:ident, $native:ty, $as_chunked:ident, $source:expr) => {
        for s in variants($source) {
            let physical = s.to_physical_repr();
            let ca = physical.$as_chunked().unwrap();
            let p = boxed(s.clone());
            for (start, count) in ranges(s.len()) {
                let mut dst = vec![<$native>::default(); count];
                let mut valid = vec![9u8; count];
                let nulls = $copy(
                    p,
                    start,
                    count,
                    dst.as_mut_ptr(),
                    count,
                    valid.as_mut_ptr(),
                    count,
                );
                let mut expected_nulls = 0;
                for k in 0..count {
                    match ca.get(start + k) {
                        Some(v) => {
                            assert_eq!((valid[k], dst[k]), (1, v));
                        }
                        None => {
                            assert_eq!(valid[k], 0);
                            expected_nulls += 1;
                        }
                    }
                }
                assert_eq!(nulls, expected_nulls);
            }
            series_drop(p);
        }
    };
}

fn ints<T: Copy>(f: impl Fn(i64) -> T) -> Vec<Option<T>> {
    let values: Vec<T> = (0..20).map(|i| f(i * 7 - 60)).collect();
    with_nulls(&values)
}

#[test]
fn physical_copies_match_get_over_chunks_and_slices() {
    check_physical!(
        series_copy_i8,
        i8,
        i8,
        Series::new("x", ints(|v| v as i8))
    );
    check_physical!(
        series_copy_i16,
        i16,
        i16,
        Series::new("x", ints(|v| v as i16 * 300))
    );
    check_physical!(
        series_copy_i32,
        i32,
        i32,
        Series::new("x", ints(|v| v as i32 * 70_000))
    );
    check_physical!(
        series_copy_i64,
        i64,
        i64,
        Series::new("x", ints(|v| v << 40))
    );
    check_physical!(
        series_copy_u8,
        u8,
        u8,
        Series::new("x", ints(|v| (v + 60) as u8))
    );
    check_physical!(
        series_copy_u16,
        u16,
        u16,
        Series::new("x", ints(|v| (v + 60) as u16 * 400))
    );
    check_physical!(
        series_copy_u32,
        u32,
        u32,
        Series::new("x", ints(|v| (v + 60) as u32 * 30_000_000))
    );
    check_physical!(
        series_copy_u64,
        u64,
        u64,
        Series::new("x", ints(|v| u64::MAX - (v + 60) as u64))
    );
    check_physical!(
        series_copy_f32,
        f32,
        f32,
        Series::new("x", ints(|v| v as f32 / 8.0))
    );
    check_physical!(
        series_copy_f64,
        f64,
        f64,
        Series::new("x", ints(|v| v as f64 / 3.0))
    );
}

#[test]
fn temporal_copies_yield_physical_values() {
    let days = Series::new("d", ints(|v| v as i32 * 1_000));
    check_physical!(
        series_copy_i32,
        i32,
        i32,
        days.cast(&DataType::Date).unwrap()
    );
    let raw = Series::new("t", ints(|v| v * 1_000_003));
    for dtype in [
        DataType::Datetime(TimeUnit::Milliseconds, None),
        DataType::Datetime(TimeUnit::Nanoseconds, None),
        DataType::Duration(TimeUnit::Microseconds),
    ] {
        check_physical!(series_copy_i64, i64, i64, raw.cast(&dtype).unwrap());
    }
    let of_day = Series::new("tod", ints(|v| (v + 60) * 1_000_000_007));
    check_physical!(
        series_copy_i64,
        i64,
        i64,
        of_day.cast(&DataType::Time).unwrap()
    );
}

#[test]
fn float_copy_is_bit_exact() {
    let values = [-0.0f64, f64::NAN, f64::INFINITY, f64::NEG_INFINITY, 5e-324];
    let s = boxed(Series::new("f", &values));
    let mut dst = [0f64; 5];
    assert_eq!(
        series_copy_f64(s, 0, 5, dst.as_mut_ptr(), 5, ptr::null_mut(), 0),
        0
    );
    for (got, want) in dst.iter().zip(values) {
        assert_eq!(got.to_bits(), want.to_bits());
    }
    series_drop(s);
}

#[test]
fn bool_copy_matches_get_over_chunks_and_slices() {
    let flags: Vec<bool> = (0..20).map(|i| i % 3 == 0).collect();
    for s in variants(Series::new("b", with_nulls(&flags))) {
        let ca = s.bool().unwrap();
        let p = boxed(s.clone());
        for (start, count) in ranges(s.len()) {
            let mut dst = vec![9u8; count];
            let mut valid = vec![9u8; count];
            let nulls = series_copy_bool(
                p,
                start,
                count,
                dst.as_mut_ptr(),
                count,
                valid.as_mut_ptr(),
                count,
            );
            let expected: Vec<Option<u8>> = (0..count)
                .map(|k| ca.get(start + k).map(u8::from))
                .collect();
            let got: Vec<Option<u8>> = (0..count)
                .map(|k| (valid[k] == 1).then_some(dst[k]))
                .collect();
            assert_eq!(got, expected);
            assert_eq!(
                nulls,
                expected.iter().filter(|v| v.is_none()).count() as i64
            );
        }
        series_drop(p);
    }
}

fn read_strs(
    p: *mut Series,
    start: usize,
    count: usize,
) -> Vec<Option<String>> {
    let size = series_str_byte_len(p, start, count) as usize;
    let mut buf = vec![0u8; size];
    let mut offsets = vec![-1i64; count + 1];
    let mut valid = vec![9u8; count];
    let nulls = series_copy_str(
        p,
        start,
        count,
        buf.as_mut_ptr(),
        size,
        offsets.as_mut_ptr(),
        count + 1,
        valid.as_mut_ptr(),
        count,
    );
    let out: Vec<Option<String>> = (0..count)
        .map(|k| {
            let bytes = &buf[offsets[k] as usize..offsets[k + 1] as usize];
            (valid[k] == 1).then(|| String::from_utf8(bytes.to_vec()).unwrap())
        })
        .collect();
    assert_eq!(nulls, out.iter().filter(|v| v.is_none()).count() as i64);
    out
}

#[test]
fn str_copy_matches_get_over_chunks_and_slices() {
    let words: Vec<String> = (0..20).map(|i| "ab😀".repeat(i % 3)).collect();
    let words: Vec<&str> = words.iter().map(String::as_str).collect();
    for s in variants(Series::new("s", with_nulls(&words))) {
        let ca = s.str().unwrap();
        let p = boxed(s.clone());
        for (start, count) in ranges(s.len()) {
            let expected: Vec<Option<String>> = (0..count)
                .map(|k| ca.get(start + k).map(str::to_owned))
                .collect();
            assert_eq!(read_strs(p, start, count), expected);
        }
        series_drop(p);
    }
}

#[test]
fn str_copy_writes_offsets_and_validity() {
    let s = boxed(Series::new(
        "s",
        &[Some("héllo"), None, Some(""), Some("😀")],
    ));
    assert_eq!(series_str_byte_len(s, 0, 4), 10);
    assert_eq!(series_str_byte_len(s, 2, 2), 4);
    let mut buf = [0u8; 10];
    let mut offsets = [-1i64; 5];
    let mut valid = [9u8; 4];
    let nulls = series_copy_str(
        s,
        0,
        4,
        buf.as_mut_ptr(),
        10,
        offsets.as_mut_ptr(),
        5,
        valid.as_mut_ptr(),
        4,
    );
    assert_eq!(nulls, 1);
    assert_eq!(offsets, [0, 6, 6, 6, 10]);
    assert_eq!(valid, [1, 0, 1, 1]);
    assert_eq!(std::str::from_utf8(&buf).unwrap(), "héllo😀");
    series_drop(s);
}

#[test]
fn refusals_write_nothing() {
    let s = boxed(Series::new("x", &[Some(1i32), None, Some(3)]));
    let mut dst = [7i32; 4];
    let mut valid = [9u8; 4];
    let d = dst.as_mut_ptr();
    let v = valid.as_mut_ptr();
    let refusals = [
        (
            series_copy_i32(ptr::null(), 0, 1, d, 4, v, 4),
            COPY_BAD_ARGUMENTS,
        ),
        (series_copy_i32(s, 2, 2, d, 4, v, 4), COPY_BAD_ARGUMENTS),
        (
            series_copy_i32(s, usize::MAX, 2, d, 4, v, 4),
            COPY_BAD_ARGUMENTS,
        ),
        (series_copy_i32(s, 0, 3, d, 2, v, 4), COPY_BAD_ARGUMENTS),
        (
            series_copy_i32(s, 0, 3, ptr::null_mut(), 3, v, 4),
            COPY_BAD_ARGUMENTS,
        ),
        (series_copy_i32(s, 0, 3, d, 4, v, 2), COPY_BAD_ARGUMENTS),
        (
            series_copy_i64(s, 0, 1, ptr::null_mut(), 1, ptr::null_mut(), 0),
            COPY_WRONG_DTYPE,
        ),
    ];
    for (got, want) in refusals {
        assert_eq!(got, want);
    }
    assert_eq!((dst, valid), ([7; 4], [9; 4]));
    let mut flags = [9u8; 3];
    assert_eq!(
        series_copy_bool(s, 0, 3, flags.as_mut_ptr(), 3, ptr::null_mut(), 0),
        COPY_WRONG_DTYPE
    );
    assert_eq!(flags, [9; 3]);
    series_drop(s);
}

#[test]
fn str_refusals_write_nothing() {
    let s = boxed(Series::new("s", &["abc", "de"]));
    let mut buf = [0u8; 5];
    let mut offsets = [-1i64; 3];
    let mut valid = [9u8; 2];
    let b = buf.as_mut_ptr();
    let o = offsets.as_mut_ptr();
    let v = valid.as_mut_ptr();
    let refusals = [
        series_copy_str(s, 0, 2, b, 4, o, 3, v, 2),
        series_copy_str(s, 0, 2, b, 5, o, 2, v, 2),
        series_copy_str(s, 0, 2, b, 5, o, 3, v, 1),
        series_copy_str(s, 0, 2, b, 5, ptr::null_mut(), 3, v, 2),
        series_copy_str(s, 1, 2, b, 5, o, 3, v, 2),
        series_copy_str(ptr::null(), 0, 2, b, 5, o, 3, v, 2),
    ];
    assert_eq!(refusals, [COPY_BAD_ARGUMENTS; 6]);
    assert_eq!((buf, offsets, valid), ([0; 5], [-1; 3], [9; 2]));
    let ints = boxed(Series::new("i", &[1i64]));
    assert_eq!(series_str_byte_len(ints, 0, 1), COPY_WRONG_DTYPE);
    assert_eq!(
        series_copy_str(ints, 0, 1, b, 5, o, 3, v, 2),
        COPY_WRONG_DTYPE
    );
    assert_eq!(series_str_byte_len(s, 1, 2), COPY_BAD_ARGUMENTS);
    series_drop(s);
    series_drop(ints);
}

#[test]
fn empty_ranges_accept_null_destinations() {
    let s = boxed(Series::new("x", &[1i64, 2]));
    let null: *mut u8 = ptr::null_mut();
    assert_eq!(series_copy_i64(s, 2, 0, ptr::null_mut(), 0, null, 0), 0);
    assert_eq!(
        series_copy_bool(s, 0, 0, null, 0, null, 0),
        COPY_WRONG_DTYPE
    );
    let text = boxed(Series::new("s", &[""]));
    let mut offsets = [-1i64; 2];
    assert_eq!(
        series_copy_str(text, 0, 1, null, 0, offsets.as_mut_ptr(), 2, null, 0),
        0
    );
    assert_eq!(offsets, [0, 0]);
    series_drop(s);
    series_drop(text);
}

#[test]
fn copy_as_f64_writes_only_its_strided_slots() {
    let s = boxed(Series::new("a", &[Some(1i64), None, Some((1 << 53) + 1)]));
    let mut dst = [-9.0f64; 12];
    assert_eq!(series_copy_as_f64(s, dst.as_mut_ptr(), 12, 2, 4, -1.5), 1);
    for (i, got) in dst.iter().enumerate() {
        let want = match i {
            2 => 1.0,
            6 => -1.5,
            10 => 9_007_199_254_740_992.0,
            _ => -9.0,
        };
        assert_eq!(*got, want, "slot {}", i);
    }
    let d = dst.as_mut_ptr();
    assert_eq!(series_copy_as_f64(s, d, 10, 2, 4, 0.0), COPY_BAD_ARGUMENTS);
    assert_eq!(series_copy_as_f64(s, d, 12, 2, 0, 0.0), COPY_BAD_ARGUMENTS);
    assert_eq!(
        series_copy_as_f64(s, d, 12, 0, usize::MAX, 0.0),
        COPY_BAD_ARGUMENTS
    );
    assert_eq!(
        series_copy_as_f64(ptr::null(), d, 12, 0, 1, 0.0),
        COPY_BAD_ARGUMENTS
    );
    let full = boxed(Series::new("b", &[0.5f64, 1.5]));
    assert_eq!(series_copy_as_f64(full, d, 12, 0, 1, 0.0), 2);
    series_drop(s);
    series_drop(full);
}

#[test]
fn copy_as_f64_reports_first_null_across_chunks() {
    let s = two_chunks(Series::new("x", &[Some(1u8), Some(2), Some(3), None]));
    let p = boxed(s);
    let mut dst = [0f64; 4];
    assert_eq!(
        series_copy_as_f64(p, dst.as_mut_ptr(), 4, 0, 1, f64::NAN),
        3
    );
    assert_eq!(&dst[..3], &[1.0, 2.0, 3.0]);
    assert!(dst[3].is_nan());
    series_drop(p);
}

#[test]
fn copy_as_f64_converts_every_accepted_dtype() {
    let cases = [
        (Series::new("i8", &[-8i8]), -8.0),
        (Series::new("i16", &[-300i16]), -300.0),
        (Series::new("i32", &[-70_000i32]), -70_000.0),
        (Series::new("i64", &[i64::MIN]), -9.223_372_036_854_776e18),
        (Series::new("u8", &[255u8]), 255.0),
        (Series::new("u16", &[65_535u16]), 65_535.0),
        (Series::new("u32", &[u32::MAX]), 4_294_967_295.0),
        (Series::new("u64", &[u64::MAX]), 1.844_674_407_370_955_2e19),
        (Series::new("f32", &[0.1f32]), 0.100_000_001_490_116_12),
        (Series::new("bool", &[true]), 1.0),
        (Series::new("bool", &[false]), 0.0),
    ];
    for (s, want) in cases {
        let p = boxed(s);
        let mut dst = [0f64; 1];
        assert_eq!(series_copy_as_f64(p, dst.as_mut_ptr(), 1, 0, 1, 0.0), 1);
        assert_eq!(dst[0], want);
        series_drop(p);
    }
    let nulls = boxed(Series::full_null("n", 3, &DataType::Null));
    let mut dst = [0f64; 3];
    assert_eq!(
        series_copy_as_f64(nulls, dst.as_mut_ptr(), 3, 0, 1, -2.5),
        0
    );
    assert_eq!(dst, [-2.5; 3]);
    series_drop(nulls);
}

#[test]
fn copy_as_f64_refuses_other_dtypes() {
    let mut dst = [0f64; 1];
    let d = dst.as_mut_ptr();
    let text = boxed(Series::new("s", &["a"]));
    let days = Series::new("d", &[1i32]);
    let date = boxed(days.cast(&DataType::Date).unwrap());
    assert_eq!(series_copy_as_f64(text, d, 1, 0, 1, 0.0), COPY_WRONG_DTYPE);
    assert_eq!(series_copy_as_f64(date, d, 1, 0, 1, 0.0), COPY_WRONG_DTYPE);
    assert_eq!(dst, [0.0]);
    let empty = boxed(Series::new_empty("e", &DataType::Float64));
    assert_eq!(series_copy_as_f64(empty, ptr::null_mut(), 0, 0, 1, 0.0), 0);
    series_drop(text);
    series_drop(date);
    series_drop(empty);
}

#[test]
fn series_drop_counts_releases() {
    let before = series_drop_count();
    series_drop(boxed(Series::new("x", &[1i32])));
    series_drop(ptr::null_mut());
    assert!(series_drop_count() > before);
}
