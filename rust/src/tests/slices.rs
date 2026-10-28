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

#[test]
fn named_sort_reads_keys_and_options() {
    let by = str_list_out(["a", "b"]);
    let descending = [1u8, 0];
    let nulls_last = [0u8, 1];
    let read = unsafe {
        named_sort(by, descending.as_ptr(), nulls_last.as_ptr(), 2, 1)
    };
    let (names, opts) = read.expect("two keys and two flags");
    assert_eq!(names, vec!["a", "b"]);
    assert_eq!(opts.descending, vec![true, false]);
    assert_eq!(opts.nulls_last, vec![false, true]);
    assert!(opts.maintain_order);
    let refused = unsafe {
        named_sort(by, descending.as_ptr(), nulls_last.as_ptr(), 1, 0)
    };
    assert_eq!(
        refused.map(|_| ()).unwrap_err().to_string(),
        "2 sort keys but 1 flags"
    );
    let null_flags =
        unsafe { named_sort(by, ptr::null(), nulls_last.as_ptr(), 2, 0) };
    assert_eq!(
        null_flags.map(|_| ()).unwrap_err().to_string(),
        "descending flags are null"
    );
    str_block_drop(by);
}

#[test]
fn deref_mut_arg_refuses_null_and_lends_the_value() {
    let refused = unsafe { deref_mut_arg(ptr::null_mut::<i64>(), "count") };
    assert_eq!(refused.unwrap_err().to_string(), "count is null");
    let mut value = 4i64;
    *unsafe { deref_mut_arg(&mut value, "count") }.unwrap() += 1;
    assert_eq!(value, 5);
}
