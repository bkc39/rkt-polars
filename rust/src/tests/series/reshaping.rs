use super::test_util::*;
use super::*;

#[test]
fn head_returns_first_n() {
    let s = make_i32("xs", &[1, 2, 3, 4, 5]);
    let h = series_head(s, 2);
    assert_eq!(series_len(h), 2);
    assert_eq!(series_ref_i32(h, 0).value, 1);
    assert_eq!(series_ref_i32(h, 1).value, 2);
    series_drop(h);
    series_drop(s);
}

#[test]
fn tail_returns_last_n() {
    let s = make_i32("xs", &[1, 2, 3, 4, 5]);
    let t = series_tail(s, 2);
    assert_eq!(series_len(t), 2);
    assert_eq!(series_ref_i32(t, 0).value, 4);
    assert_eq!(series_ref_i32(t, 1).value, 5);
    series_drop(t);
    series_drop(s);
}

#[test]
fn slice_offset_length() {
    let s = make_i32("xs", &[10, 20, 30, 40, 50]);
    let sl = series_slice(s, 1, 3);
    assert_eq!(series_len(sl), 3);
    assert_eq!(series_ref_i32(sl, 0).value, 20);
    assert_eq!(series_ref_i32(sl, 2).value, 40);
    series_drop(sl);
    series_drop(s);
}

#[test]
fn reverse_reverses_order() {
    let s = make_i32("xs", &[1, 2, 3]);
    let r = series_reverse(s);
    assert_eq!(series_ref_i32(r, 0).value, 3);
    assert_eq!(series_ref_i32(r, 2).value, 1);
    series_drop(r);
    series_drop(s);
}

#[test]
fn drop_nulls_collapses_length() {
    let s = make_opt_i32("xs", &[Some(1), None, Some(3), None, Some(5)]);
    let d = series_drop_nulls(s);
    assert_eq!(series_len(d), 3);
    // The remaining values keep their order.
    assert_eq!(series_ref_i32(d, 0).value, 1);
    assert_eq!(series_ref_i32(d, 1).value, 3);
    assert_eq!(series_ref_i32(d, 2).value, 5);
    series_drop(d);
    series_drop(s);
}

#[test]
fn unique_dedupes_entries() {
    let s = make_i32("xs", &[1, 2, 2, 3, 3, 3]);
    let u = series_unique(s);
    // Order isn't guaranteed; check the count + sum.
    assert_eq!(series_len(u), 3);
    let mut got: Vec<i32> = (0..series_len(u))
        .map(|i| series_ref_i32(u, i).value)
        .collect();
    got.sort();
    assert_eq!(got, vec![1, 2, 3]);
    series_drop(u);
    series_drop(s);
}

#[test]
fn sort_ascending_and_descending() {
    let s = make_i32("xs", &[3, 1, 2]);
    let asc = series_sort_with_options(s, 0, 0);
    assert_eq!(series_ref_i32(asc, 0).value, 1);
    assert_eq!(series_ref_i32(asc, 2).value, 3);
    series_drop(asc);
    let desc = series_sort_with_options(s, 1, 0);
    assert_eq!(series_ref_i32(desc, 0).value, 3);
    assert_eq!(series_ref_i32(desc, 2).value, 1);
    series_drop(desc);
    series_drop(s);
}

fn sorted_i32s(
    s: *mut Series,
    descending: u8,
    nulls_last: u8,
) -> Vec<Option<i32>> {
    let out = series_sort_with_options(s, descending, nulls_last);
    assert!(!out.is_null(), "{:?}", recorded_error());
    let v = opt_i32s(out);
    series_drop(out);
    v
}

#[test]
fn sort_places_nulls_by_flag() {
    let s = make_opt_i32("xs", &[Some(2), None, Some(1)]);
    assert_eq!(sorted_i32s(s, 0, 0), vec![None, Some(1), Some(2)]);
    assert_eq!(sorted_i32s(s, 0, 1), vec![Some(1), Some(2), None]);
    assert_eq!(sorted_i32s(s, 1, 0), vec![None, Some(2), Some(1)]);
    assert_eq!(sorted_i32s(s, 1, 1), vec![Some(2), Some(1), None]);
    series_drop(s);
}

#[test]
fn sort_places_boolean_nulls_by_flag() {
    let (t, f) = (Some(true), Some(false));
    let s = make_opt_bool("b", &[t, None, f, t]);
    let cases = [
        (0, 0, [None, f, t, t]),
        (0, 1, [f, t, t, None]),
        (1, 0, [None, t, t, f]),
        (1, 1, [t, t, f, None]),
    ];
    for (descending, nulls_last, expected) in cases {
        let out = series_sort_with_options(s, descending, nulls_last);
        assert!(!out.is_null(), "{:?}", recorded_error());
        assert_eq!(opt_bools(out), expected.to_vec());
        series_drop(out);
    }
    series_drop(s);
}

#[test]
fn sort_of_a_sorted_series_honours_nulls_last() {
    let s = make_opt_i32("xs", &[Some(3), None, Some(1), None, Some(2)]);
    for (descending, expected) in [(0, [1, 2, 3]), (1, [3, 2, 1])] {
        let once = series_sort_with_options(s, descending, 0);
        let mut want: Vec<Option<i32>> =
            expected.iter().map(|&v| Some(v)).collect();
        want.extend([None, None]);
        assert_eq!(sorted_i32s(once, descending, 1), want);
        series_drop(once);
    }
    series_drop(s);
}

#[test]
fn reshaping_null_series_returns_null() {
    assert!(series_head(ptr::null_mut(), 1).is_null());
    assert!(series_tail(ptr::null_mut(), 1).is_null());
    assert!(series_slice(ptr::null_mut(), 0, 1).is_null());
    assert!(series_reverse(ptr::null_mut()).is_null());
    assert!(series_drop_nulls(ptr::null_mut()).is_null());
    assert!(series_unique(ptr::null_mut()).is_null());
    assert!(series_sort_with_options(ptr::null_mut(), 0, 0).is_null());
    assert_eq!(recorded_error().as_deref(), Some("series is null"));
}
