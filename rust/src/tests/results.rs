use super::test_util::*;
use super::*;

fn take<T>(p: *mut T) -> T {
    assert!(!p.is_null());
    *unsafe { Box::from_raw(p) }
}

#[test]
fn boxed_result_records_an_error_and_returns_null() {
    clear_last_error();
    let p = boxed_result(|| -> PolarsResult<i32> {
        Err(polars_err!(ComputeError: "no luck"))
    });
    assert!(p.is_null());
    assert_eq!(recorded_error().as_deref(), Some("no luck"));
}

#[test]
fn boxed_result_records_a_panic_and_returns_null() {
    clear_last_error();
    let p = boxed_result(|| -> PolarsResult<i32> { panic!("boom") });
    assert!(p.is_null());
    assert_eq!(recorded_error().as_deref(), Some("polars panicked: boom"));
}

#[test]
fn boxed_result_clears_a_stale_reason_on_success() {
    set_last_error("stale");
    assert_eq!(take(boxed_result(|| Ok(7))), 7);
    assert_eq!(recorded_error(), None);
}

#[test]
fn scalar_result_records_an_error_and_returns_failed() {
    clear_last_error();
    let v = scalar_result(-1, || -> PolarsResult<i32> {
        Err(polars_err!(ComputeError: "no luck"))
    });
    assert_eq!(v, -1);
    assert_eq!(recorded_error().as_deref(), Some("no luck"));
}

#[test]
fn scalar_result_records_a_panic_and_returns_failed() {
    clear_last_error();
    let v = scalar_result(-1, || -> PolarsResult<i32> { panic!("boom") });
    assert_eq!(v, -1);
    assert_eq!(recorded_error().as_deref(), Some("polars panicked: boom"));
}

#[test]
fn scalar_result_clears_a_stale_reason_on_success() {
    set_last_error("stale");
    assert_eq!(scalar_result(-1, || Ok(7)), 7);
    assert_eq!(recorded_error(), None);
}

#[test]
fn boxed_unguarded_records_an_error_and_returns_null() {
    clear_last_error();
    let p = boxed_unguarded(|| -> PolarsResult<i32> {
        Err(polars_err!(ComputeError: "no luck"))
    });
    assert!(p.is_null());
    assert_eq!(recorded_error().as_deref(), Some("no luck"));
}

#[test]
fn boxed_unguarded_clears_a_stale_reason_on_success() {
    set_last_error("stale");
    assert_eq!(take(boxed_unguarded(|| Ok(7))), 7);
    assert_eq!(recorded_error(), None);
}
