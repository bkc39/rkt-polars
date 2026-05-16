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
    let asc = series_sort(s, 0);
    assert_eq!(series_ref_i32(asc, 0).value, 1);
    assert_eq!(series_ref_i32(asc, 2).value, 3);
    series_drop(asc);
    let desc = series_sort(s, 1);
    assert_eq!(series_ref_i32(desc, 0).value, 3);
    assert_eq!(series_ref_i32(desc, 2).value, 1);
    series_drop(desc);
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
    assert!(series_sort(ptr::null_mut(), 0).is_null());
}
