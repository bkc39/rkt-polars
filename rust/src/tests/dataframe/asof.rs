use super::test_util::*;
use super::*;

/// Quotes (left) and trades (right). Each side is sorted by the
/// join key — a prerequisite for asof joins.
fn make_quotes_trades() -> (*mut DataFrame, *mut DataFrame, [*mut Series; 4]) {
    let lk = make_i64("ts", &[1, 5, 10]);
    let lv = make_i32("quote", &[100, 200, 300]);
    let rk = make_i64("ts", &[2, 6, 11]);
    let rw = make_i32("trade", &[1000, 2000, 3000]);
    let left = make_df(&[lk, lv]);
    let right = make_df(&[rk, rw]);
    (left, right, [lk, lv, rk, rw])
}

fn run_asof(
    left: *mut DataFrame,
    right: *mut DataFrame,
    strategy: CompatAsofStrategy,
) -> *mut DataFrame {
    let lk = str_block("ts");
    let rk = str_block("ts");
    dataframe_join_asof_v2(
        left,
        right,
        lk.as_ptr(),
        rk.as_ptr(),
        strategy as i32,
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
fn asof_backward_strategy() {
    let (left, right, series) = make_quotes_trades();
    let out = run_asof(left, right, CompatAsofStrategy::Backward);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), dataframe_height(left));
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn asof_forward_strategy() {
    let (left, right, series) = make_quotes_trades();
    let out = run_asof(left, right, CompatAsofStrategy::Forward);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), dataframe_height(left));
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn asof_nearest_strategy() {
    let (left, right, series) = make_quotes_trades();
    let out = run_asof(left, right, CompatAsofStrategy::Nearest);
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), dataframe_height(left));
    dataframe_drop(out);
    cleanup(left, right, series);
}

#[test]
fn asof_invalid_strategy_returns_null() {
    let (left, right, series) = make_quotes_trades();
    let lk = str_block("ts");
    let rk = str_block("ts");
    let out =
        dataframe_join_asof_v2(left, right, lk.as_ptr(), rk.as_ptr(), 999);
    assert!(out.is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("unknown asof strategy 999")
    );
    let missing = str_block("nope");
    let out = dataframe_join_asof_v2(
        left,
        right,
        missing.as_ptr(),
        rk.as_ptr(),
        CompatAsofStrategy::Backward as i32,
    );
    assert!(out.is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("\"nope\""), "{}", reason);
    cleanup(left, right, series);
}

#[test]
fn asof_options_with_by_keys() {
    // Same shape but each side carries a `by` partition column.
    let lk = make_i64("ts", &[1, 5, 1, 5]);
    let lby = make_str("g", &["a", "a", "b", "b"]);
    let lv = make_i32("v", &[10, 20, 30, 40]);
    let rk = make_i64("ts", &[2, 6, 2, 6]);
    let rby = make_str("g", &["a", "a", "b", "b"]);
    let rw = make_i32("w", &[100, 200, 300, 400]);
    let left = make_df(&[lk, lby, lv]);
    let right = make_df(&[rk, rby, rw]);

    let ts_l = str_block("ts");
    let ts_r = str_block("ts");
    let lby_arr = str_list_block(&["g"]);
    let rby_arr = str_list_block(&["g"]);
    let out = dataframe_join_asof_options_v2(
        left,
        right,
        ts_l.as_ptr(),
        ts_r.as_ptr(),
        CompatAsofStrategy::Backward as i32,
        lby_arr.as_ptr(),
        rby_arr.as_ptr(),
        CompatAsofToleranceKind::None as i32,
        0,
        0.0,
    );
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), dataframe_height(left));
    dataframe_drop(out);
    dataframe_drop(left);
    dataframe_drop(right);
    for s in [lk, lby, lv, rk, rby, rw] {
        series_drop(s);
    }
}

#[test]
fn asof_options_with_integer_tolerance() {
    let (left, right, series) = make_quotes_trades();
    let lk = str_block("ts");
    let rk = str_block("ts");
    let out = dataframe_join_asof_options_v2(
        left,
        right,
        lk.as_ptr(),
        rk.as_ptr(),
        CompatAsofStrategy::Backward as i32,
        ptr::null(),
        ptr::null(),
        CompatAsofToleranceKind::Integer as i32,
        3,
        0.0,
    );
    assert!(!out.is_null());
    assert_eq!(dataframe_height(out), dataframe_height(left));
    dataframe_drop(out);
    cleanup(left, right, series);
}
