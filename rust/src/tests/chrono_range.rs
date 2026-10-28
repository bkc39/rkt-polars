use super::test_util::*;
use super::*;

const DATE_CAUSE: &str = "out-of-range date";
const DATETIME_CAUSE: &str = "invalid or out-of-range datetime";

fn temporal(tag: CompatDTypeTag, unit: CompatTimeUnit) -> CompatDType {
    CompatDType {
        tag: tag as i32,
        time_unit: unit as i32,
        flags: 0,
        array_width: 0,
    }
}

fn cast_to(
    raw: *mut Series,
    tag: CompatDTypeTag,
    unit: CompatTimeUnit,
) -> *mut Series {
    let out = series_cast(raw, temporal(tag, unit));
    series_drop(raw);
    assert!(!out.is_null());
    out
}

fn past_chrono_date() -> *mut Series {
    cast_to(
        make_i32("d", &[0, 2_000_000_000]),
        CompatDTypeTag::Date,
        CompatTimeUnit::None,
    )
}

fn past_chrono_datetime() -> *mut Series {
    cast_to(
        make_i64("t", &[i64::MAX]),
        CompatDTypeTag::Datetime,
        CompatTimeUnit::Milliseconds,
    )
}

fn assert_panic_reason(cause: &str) {
    let reason = recorded_error().expect("a reason");
    assert_eq!(reason, format!("polars panicked: {}", cause));
}

fn assert_frame_refused(
    columns: &[*mut Series],
    cause: &str,
    refused: impl FnOnce(*mut DataFrame) -> bool,
) {
    let df = make_df(columns);
    set_last_error("stale");
    assert!(refused(df));
    assert_panic_reason(cause);
    dataframe_drop(df);
    columns.iter().for_each(|&s| series_drop(s));
}

#[test]
fn printing_a_frame_with_a_date_past_chrono_records_the_panic() {
    assert_frame_refused(&[past_chrono_date()], DATE_CAUSE, |df| {
        dataframe_to_string_v2(df).is_null()
    });
}

#[test]
fn printing_a_frame_with_a_datetime_past_chrono_records_the_panic() {
    assert_frame_refused(&[past_chrono_datetime()], DATETIME_CAUSE, |df| {
        dataframe_to_string_v2(df).is_null()
    });
}

#[test]
fn printing_a_frame_in_range_clears_the_reason() {
    let dates = make_i32("d", &[0]);
    let df = make_df(&[dates]);
    set_last_error("stale");
    let shown = take_str(dataframe_to_string_v2(df));
    assert!(shown.contains("shape: (1, 1)"), "{}", shown);
    assert_eq!(recorded_error(), None);
    dataframe_drop(df);
    series_drop(dates);
}

#[test]
fn an_unnamed_expression_over_a_date_past_chrono_has_no_output_name() {
    let dates = past_chrono_date();
    let values = expr_lit_series(dates);
    let all = expr_all();
    let member = expr_is_in(all, values);
    set_last_error("stale");
    assert!(expr_meta_output_name_v2(member).is_null());
    assert_panic_reason(DATE_CAUSE);
    expr_drop(member);
    expr_drop(all);
    expr_drop(values);
    series_drop(dates);
}

#[test]
fn printing_an_expression_over_a_date_past_chrono_records_the_panic() {
    let dates = past_chrono_date();
    let name = cstr("x");
    let column = expr_col(name.as_ptr());
    let values = expr_lit_series(dates);
    let member = expr_is_in(column, values);
    assert!(expr_to_string_v2(member).is_null());
    assert_panic_reason(DATE_CAUSE);
    set_last_error("stale");
    assert_eq!(take_str(expr_to_string_v2(column)), "col(\"x\")");
    assert_eq!(recorded_error(), None);
    expr_drop(member);
    expr_drop(values);
    expr_drop(column);
    series_drop(dates);
}

#[test]
fn casting_a_value_past_chrono_to_a_string_records_the_panic() {
    let string = temporal(CompatDTypeTag::String, CompatTimeUnit::None);
    for (series, cause) in [
        (past_chrono_date(), DATE_CAUSE),
        (past_chrono_datetime(), DATETIME_CAUSE),
    ] {
        set_last_error("stale");
        assert!(series_cast(series, string).is_null());
        assert_panic_reason(cause);
        series_drop(series);
    }
}

#[test]
fn pivoting_on_a_date_past_chrono_records_the_panic() {
    let on = cstr("d");
    let index = cstr("k");
    let values = cstr("x");
    let (on, index, values) =
        ([on.as_ptr()], [index.as_ptr()], [values.as_ptr()]);
    assert_frame_refused(
        &[
            past_chrono_date(),
            make_str("k", &["a", "b"]),
            make_i32("x", &[1, 2]),
        ],
        DATE_CAUSE,
        |df| {
            dataframe_pivot(
                df,
                on.as_ptr(),
                1,
                index.as_ptr(),
                1,
                values.as_ptr(),
                1,
                CompatPivotAgg::First as i32,
            )
            .is_null()
        },
    );
}

#[test]
fn unpivoting_a_date_past_chrono_into_strings_records_the_panic() {
    let d = cstr("d");
    let k = cstr("k");
    let i = cstr("i");
    let (on, index) = ([d.as_ptr(), k.as_ptr()], [i.as_ptr()]);
    assert_frame_refused(
        &[
            past_chrono_date(),
            make_str("k", &["a", "b"]),
            make_i32("i", &[1, 2]),
        ],
        DATE_CAUSE,
        |df| dataframe_unpivot(df, on.as_ptr(), 2, index.as_ptr(), 1).is_null(),
    );
}

#[test]
fn reading_past_the_end_of_a_series_reads_nothing() {
    let s = make_i64("a", &[1]);
    assert_eq!(series_ref_i64(s, 0).value, 1);
    assert_eq!(series_ref_i64(s, 5).valid, 0);
    assert_eq!(series_ref_i64(s, usize::MAX).valid, 0);
    series_drop(s);
}

#[test]
fn an_impossible_date_and_time_builds_no_series() {
    let name = cstr("a");
    let data = [YMDHMS {
        year: 2021,
        month: 2,
        day: 30,
        hour: 0,
        minute: 0,
        second: 0,
    }];
    assert!(
        series_new_ymdhms(name.as_ptr(), data.as_ptr(), data.len()).is_null()
    );
}
