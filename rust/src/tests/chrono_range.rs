use super::test_util::*;
use super::*;

fn temporal(tag: CompatDTypeTag, unit: CompatTimeUnit) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: unit as i32,
        flags: 0,
        array_width: 0,
    }
}

fn past_chrono_date() -> *mut Series {
    let raw = make_i32("d", &[0, 2_000_000_000]);
    let dates =
        series_cast(raw, temporal(CompatDTypeTag::Date, CompatTimeUnit::None));
    series_drop(raw);
    assert!(!dates.is_null());
    dates
}

fn past_chrono_datetime() -> *mut Series {
    let raw = make_i64("t", &[i64::MAX]);
    let stamps = series_cast(
        raw,
        temporal(CompatDTypeTag::Datetime, CompatTimeUnit::Milliseconds),
    );
    series_drop(raw);
    assert!(!stamps.is_null());
    stamps
}

fn assert_panic_reason(cause: &str) {
    let reason = recorded_error().expect("a reason");
    assert_eq!(reason, format!("polars panicked: {}", cause));
}

#[test]
fn printing_a_frame_with_a_date_past_chrono_records_the_panic() {
    let dates = past_chrono_date();
    let df = make_df(&[dates]);
    assert!(dataframe_to_string(df).is_null());
    assert_panic_reason("out-of-range date");
    dataframe_drop(df);
    series_drop(dates);
}

#[test]
fn printing_a_frame_with_a_datetime_past_chrono_records_the_panic() {
    let stamps = past_chrono_datetime();
    let df = make_df(&[stamps]);
    assert!(dataframe_to_string(df).is_null());
    assert_panic_reason("invalid or out-of-range datetime");
    dataframe_drop(df);
    series_drop(stamps);
}

#[test]
fn printing_a_frame_in_range_clears_the_reason() {
    let dates = make_i32("d", &[0]);
    let df = make_df(&[dates]);
    set_last_error("stale");
    let shown = take_cstring(dataframe_to_string(df));
    assert!(shown.contains("shape: (1, 1)"), "{}", shown);
    assert_eq!(recorded_error(), None);
    dataframe_drop(df);
    series_drop(dates);
}

#[test]
fn printing_an_expression_over_a_date_past_chrono_records_the_panic() {
    let dates = past_chrono_date();
    let name = cstr("x");
    let column = expr_col(name.as_ptr());
    let values = expr_lit_series(dates);
    let member = expr_is_in(column, values);
    assert!(expr_to_string(member).is_null());
    assert_panic_reason("out-of-range date");
    set_last_error("stale");
    assert_eq!(take_cstring(expr_to_string(column)), "col(\"x\")");
    assert_eq!(recorded_error(), None);
    expr_drop(member);
    expr_drop(values);
    expr_drop(column);
    series_drop(dates);
}
