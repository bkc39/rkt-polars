use super::*;

#[test]
fn slice_or_empty_null_and_zero_is_empty() {
    let s = unsafe { slice_or_empty(ptr::null::<i64>(), 0) };
    assert_eq!(s, Some(&[][..]));
}

#[test]
fn slice_or_empty_null_with_rows_is_refused() {
    assert_eq!(unsafe { slice_or_empty(ptr::null::<i64>(), 3) }, None);
}

#[test]
fn slice_or_empty_reads_non_null() {
    let data = [4i64, 5, 6];
    let s = unsafe { slice_or_empty(data.as_ptr(), data.len()) };
    assert_eq!(s, Some(&data[..]));
    assert_eq!(unsafe { slice_or_empty(data.as_ptr(), 0) }, Some(&[][..]));
}

#[test]
fn collectors_take_null_and_zero() {
    assert_eq!(unsafe { collect_c_strings(ptr::null(), 0) }, Some(vec![]));
    assert_eq!(unsafe { collect_c_strings(ptr::null(), 2) }, None);
    assert!(
        unsafe { collect_exprs(ptr::null(), 0) }.is_some_and(|v| v.is_empty())
    );
    assert!(unsafe { collect_exprs(ptr::null(), 2) }.is_none());
}
