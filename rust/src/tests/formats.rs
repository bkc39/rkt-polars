use super::test_util::*;
use super::*;

const US: i32 = CompatTimeUnit::Microseconds as i32;

fn column() -> *mut Expr {
    let s = str_block("s");
    expr_col_v2(s.as_ptr())
}

fn evaluate(data: Series, e: *mut Expr) -> Series {
    assert!(!e.is_null(), "null result: {:?}", recorded_error());
    let expr = unsafe { (*e).clone() };
    expr_drop(e);
    DataFrame::new_infer_height(vec![Column::from(data)])
        .unwrap()
        .lazy()
        .select([expr.alias("v")])
        .collect()
        .unwrap()
        .column("v")
        .unwrap()
        .as_materialized_series()
        .clone()
}

fn texts(values: &[&str]) -> Series {
    Series::new("s".into(), values)
}

fn shown(s: &Series) -> Vec<String> {
    s.cast(&DataType::String)
        .unwrap()
        .str()
        .unwrap()
        .iter()
        .map(|v| v.unwrap().to_string())
        .collect()
}

#[test]
fn a_parse_format_keeps_its_nul() {
    let s = column();
    let date = str_block("%Y\0%m\0%d");
    let parsed = evaluate(
        texts(&["2020\x0001\x0002"]),
        expr_str_to_date_v2(s, date.as_ptr(), 1, 1, 1),
    );
    assert_eq!(parsed.dtype(), &DataType::Date);
    assert_eq!(shown(&parsed), ["2020-01-02"]);

    let datetime = str_block("%Y\0%m\0%d %H:%M");
    let parsed = evaluate(
        texts(&["2020\x0001\x0002 03:04"]),
        expr_str_to_datetime_v2(s, datetime.as_ptr(), US, 1, 1, 1),
    );
    assert_eq!(shown(&parsed), ["2020-01-02 03:04:00.000000"]);

    let (utc, raise) = (cstr("UTC"), cstr("raise"));
    let parsed = evaluate(
        texts(&["2020\x0001\x0002 03:04"]),
        expr_str_to_datetime_tz_v2(
            s,
            datetime.as_ptr(),
            US,
            utc.as_ptr(),
            raise.as_ptr(),
            1,
            1,
            1,
        ),
    );
    assert_eq!(shown(&parsed), ["2020-01-02 03:04:00.000000+00:00"]);

    let time = str_block("%H\0%M");
    let parsed = evaluate(
        texts(&["03\x0004"]),
        expr_str_to_time_v2(s, time.as_ptr(), 1, 1, 1),
    );
    assert_eq!(shown(&parsed), ["03:04:00"]);
    expr_drop(s);
}

#[test]
fn a_format_cut_at_its_nul_fails_to_parse() {
    let cut = str_block("%Y");
    let s = column();
    let e = expr_str_to_date_v2(s, cut.as_ptr(), 1, 1, 1);
    let expr = unsafe { (*e).clone() };
    expr_drop(e);
    expr_drop(s);
    let failed = DataFrame::new_infer_height(vec![Column::from(texts(&[
        "2020\x0001\x0002",
    ]))])
    .unwrap()
    .lazy()
    .select([expr])
    .collect();
    assert!(failed.is_err());
}

#[test]
fn a_strftime_format_keeps_its_nul() {
    let dates = Series::new("s".into(), [18263i32])
        .cast(&DataType::Date)
        .unwrap();
    let format = str_block("%Y\0%m");
    let s = column();
    let out = evaluate(dates, expr_dt_strftime_v2(s, format.as_ptr()));
    assert_eq!(shown(&out), ["2020\x0001"]);
    expr_drop(s);
}

#[test]
fn every_format_v2_refuses_a_malformed_block_with_its_cause() {
    let bad: Vec<u64> = vec![2, 1];
    let bad = bad.as_ptr();
    let (utc, raise) = (cstr("UTC"), cstr("raise"));
    let e = column();
    let rows: Vec<(&str, Box<dyn Fn() -> *mut Expr + '_>)> = vec![
        (
            "expr_str_to_date_v2",
            Box::new(|| expr_str_to_date_v2(e, bad, 1, 1, 1)),
        ),
        (
            "expr_str_to_datetime_v2",
            Box::new(|| expr_str_to_datetime_v2(e, bad, US, 1, 1, 1)),
        ),
        (
            "expr_str_to_datetime_tz_v2",
            Box::new(|| {
                expr_str_to_datetime_tz_v2(
                    e,
                    bad,
                    US,
                    utc.as_ptr(),
                    raise.as_ptr(),
                    1,
                    1,
                    1,
                )
            }),
        ),
        (
            "expr_str_to_time_v2",
            Box::new(|| expr_str_to_time_v2(e, bad, 1, 1, 1)),
        ),
        (
            "expr_dt_strftime_v2",
            Box::new(|| expr_dt_strftime_v2(e, bad)),
        ),
    ];
    for (name, call) in rows {
        assert!(call().is_null(), "{name} accepted a malformed block");
        assert_eq!(
            recorded_error(),
            Some(StrError::Truncated.to_string()),
            "{name}"
        );
    }
    assert!(expr_dt_strftime_v2(e, ptr::null()).is_null());
    assert_eq!(recorded_error().as_deref(), Some("the format is null"));
    assert!(expr_str_to_datetime_v2(e, ptr::null(), 99, 1, 1, 1).is_null());
    assert_eq!(recorded_error().as_deref(), Some("unknown time unit 99"));
    expr_drop(e);
}
