use super::test_util::*;
use super::*;

/// Left = {k:[1,2,3], v:[10,20,30]}.
/// Right = {k:[2,3,4], w:[200,300,400]}.
fn make_left_right() -> (*mut DataFrame, *mut DataFrame, [*mut Series; 4]) {
    let lk = make_i32("k", &[1, 2, 3]);
    let lv = make_i32("v", &[10, 20, 30]);
    let rk = make_i32("k", &[2, 3, 4]);
    let rw = make_i32("w", &[200, 300, 400]);
    let left = make_df(&[lk, lv]);
    let right = make_df(&[rk, rw]);
    (left, right, [lk, lv, rk, rw])
}

fn join_on_k(
    left: *mut DataFrame,
    right: *mut DataFrame,
    kind: CompatJoinKind,
) -> *mut DataFrame {
    let lk = cstr("k");
    let rk = cstr("k");
    let lon: [*const c_char; 1] = [lk.as_ptr()];
    let ron: [*const c_char; 1] = [rk.as_ptr()];
    dataframe_join(
        left,
        right,
        lon.as_ptr(),
        lon.len(),
        ron.as_ptr(),
        ron.len(),
        kind as i32,
    )
}

fn cleanup(
    left: *mut DataFrame,
    right: *mut DataFrame,
    series: [*mut Series; 4],
) {
    dataframe_drop(left);
    dataframe_drop(right);
    for s in series {
        series_drop(s);
    }
}

#[test]
fn join_inner_returns_only_matches() {
    let (left, right, series) = make_left_right();
    let out = join_on_k(left, right, CompatJoinKind::Inner);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 2);
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn join_left_keeps_all_left_rows() {
    let (left, right, series) = make_left_right();
    let out = join_on_k(left, right, CompatJoinKind::Left);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 3);
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn join_outer_keeps_all_rows_from_both_sides() {
    let (left, right, series) = make_left_right();
    let out = join_on_k(left, right, CompatJoinKind::Outer);
    assert!(!out.is_null());
    // 2 matched (k=2,3) + 1 left-only (k=1) + 1 right-only (k=4)
    assert_eq!(dataframe_height(out), 4);
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn join_cross_produces_cartesian_product() {
    let (left, right, series) = make_left_right();
    // Cross join ignores the `on` arrays — pass empties.
    let out = dataframe_join(
        left,
        right,
        ptr::null(),
        0,
        ptr::null(),
        0,
        CompatJoinKind::Cross as i32,
    );
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 3 * 3);
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn join_semi_returns_left_with_matches() {
    let (left, right, series) = make_left_right();
    let out = join_on_k(left, right, CompatJoinKind::Semi);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 2);
    assert_eq!(dataframe_width(out), 2); // semi returns left cols
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn join_anti_returns_left_without_matches() {
    let (left, right, series) = make_left_right();
    let out = join_on_k(left, right, CompatJoinKind::Anti);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), 1);
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn join_invalid_kind_returns_null() {
    let (left, right, series) = make_left_right();
    let lk = cstr("k");
    let rk = cstr("k");
    let lon: [*const c_char; 1] = [lk.as_ptr()];
    let ron: [*const c_char; 1] = [rk.as_ptr()];
    // 99 isn't a CompatJoinKind variant.
    let out = dataframe_join(
        left,
        right,
        lon.as_ptr(),
        lon.len(),
        ron.as_ptr(),
        ron.len(),
        99,
    );
    assert!(out.is_null());
    cleanup(left, right, series);
}

#[test]
fn join_null_inputs_return_null() {
    let (left, right, series) = make_left_right();
    assert!(join_on_k(ptr::null_mut(), right, CompatJoinKind::Inner).is_null());
    assert!(join_on_k(left, ptr::null_mut(), CompatJoinKind::Inner).is_null());
    cleanup(left, right, series);
}

#[test]
fn join_empty_on_arrays_return_null_for_non_cross() {
    // Inner / left / outer / semi / anti require at least one key.
    let (left, right, series) = make_left_right();
    let out = dataframe_join(
        left,
        right,
        ptr::null(),
        0,
        ptr::null(),
        0,
        CompatJoinKind::Inner as i32,
    );
    assert!(out.is_null());
    cleanup(left, right, series);
}
