use super::test_util::*;
use super::*;

const US: i32 = CompatTimeUnit::Microseconds as i32;
const NS: i32 = CompatTimeUnit::Nanoseconds as i32;

fn zone(name: &str) -> TimeZone {
    TimeZone::opt_try_new(Some(name)).unwrap().unwrap()
}

fn utc_us(y: i32, m: u32, d: u32, h: u32, min: u32) -> i64 {
    NaiveDate::from_ymd_opt(y, m, d)
        .unwrap()
        .and_hms_opt(h, min, 0)
        .unwrap()
        .and_utc()
        .timestamp_micros()
}

fn owned(p: *mut Series) -> Series {
    assert!(!p.is_null(), "null result: {:?}", recorded_error());
    unsafe { *Box::from_raw(p) }
}

fn boxed(s: Series) -> *mut Series {
    Box::into_raw(Box::new(s))
}

fn naive(values: &[Option<i64>]) -> Series {
    Series::new("t".into(), values)
        .cast(&DataType::Datetime(TimeUnit::Microseconds, None))
        .unwrap()
}

fn zoned(values: &[Option<i64>], tz: &str) -> Series {
    Series::new("t".into(), values)
        .cast(&DataType::Datetime(TimeUnit::Microseconds, Some(zone(tz))))
        .unwrap()
}

fn physical(s: &Series) -> Vec<Option<i64>> {
    s.to_physical_repr()
        .cast(&DataType::Int64)
        .unwrap()
        .i64()
        .unwrap()
        .iter()
        .collect()
}

fn evaluate(frame: Vec<Series>, e: Expr) -> PolarsResult<Series> {
    let columns = frame.into_iter().map(Column::from).collect();
    DataFrame::new_infer_height(columns)?
        .lazy()
        .select([e.alias("v")])
        .collect()
        .map(|df| df.column("v").unwrap().as_materialized_series().clone())
}

fn column(name: &str) -> *mut Expr {
    let n = cstr(name);
    expr_col(n.as_ptr())
}

fn take_expr(p: *mut Expr) -> Expr {
    assert!(!p.is_null(), "null result: {:?}", recorded_error());
    let e = unsafe { (*p).clone() };
    expr_drop(p);
    e
}

fn replace(
    s: &Series,
    tz: Option<&str>,
    ambiguous: &str,
    non_existent: &str,
) -> *mut Series {
    let tz = tz.map(cstr);
    let (a, n) = (cstr(ambiguous), cstr(non_existent));
    let p = boxed(s.clone());
    let out = series_dt_replace_time_zone(
        p,
        tz.as_ref().map_or(ptr::null(), |t| t.as_ptr()),
        a.as_ptr(),
        n.as_ptr(),
    );
    series_drop(p);
    out
}

#[test]
fn series_time_zone_names_only_a_zoned_datetime() {
    let brussels = boxed(zoned(&[Some(0)], "Europe/Brussels"));
    assert_eq!(take_cstring(series_time_zone(brussels)), "Europe/Brussels");
    let plain = boxed(naive(&[Some(0)]));
    assert!(series_time_zone(plain).is_null());
    let ints = make_i64("i", &[1]);
    assert!(series_time_zone(ints).is_null());
    assert!(series_time_zone(ptr::null()).is_null());
    for p in [brussels, plain, ints] {
        series_drop(p);
    }
    let flagged = compat_dtype_from_polars(&DataType::Datetime(
        TimeUnit::Microseconds,
        Some(zone("UTC")),
    ));
    assert_eq!(flagged.flags, 1);
}

#[test]
fn cast_to_a_zone_reads_naive_values_and_integers_as_utc() {
    let instant = utc_us(2021, 3, 27, 12, 0);
    let tz = cstr("Europe/Brussels");
    for source in [
        Series::new("t".into(), [Some(instant), None]),
        naive(&[Some(instant), None]),
        zoned(&[Some(instant), None], "Asia/Kathmandu"),
    ] {
        let p = boxed(source);
        let out = owned(series_cast_datetime_tz(p, US, tz.as_ptr()));
        assert_eq!(
            out.dtype(),
            &DataType::Datetime(
                TimeUnit::Microseconds,
                Some(zone("Europe/Brussels"))
            )
        );
        assert_eq!(physical(&out), vec![Some(instant), None]);
        series_drop(p);
    }
    let p = boxed(naive(&[Some(1_500)]));
    let ns = owned(series_cast_datetime_tz(p, NS, tz.as_ptr()));
    assert_eq!(physical(&ns), vec![Some(1_500_000)]);
    series_drop(p);
}

#[test]
fn a_zone_is_canonical_and_checked() {
    let p = boxed(naive(&[Some(0)]));
    for (given, canonical) in [
        ("+01:00", "Etc/GMT-1"),
        ("utc", "UTC"),
        ("Etc/UTC", "Etc/UTC"),
    ] {
        let tz = cstr(given);
        let out = series_cast_datetime_tz(p, US, tz.as_ptr());
        assert_eq!(take_cstring(series_time_zone(out)), canonical);
        series_drop(out);
    }
    for (given, reason) in [
        ("Mars/Base", "unable to parse time zone: 'Mars/Base'"),
        ("europe/brussels", "did you mean 'Europe/Brussels'"),
        ("*", "not a time zone: '*'"),
        ("", "not a time zone: ''"),
    ] {
        let tz = cstr(given);
        assert!(series_cast_datetime_tz(p, US, tz.as_ptr()).is_null());
        let recorded = recorded_error().unwrap();
        assert!(recorded.contains(reason), "{given}: {recorded}");
    }
    assert!(series_cast_datetime_tz(p, US, ptr::null()).is_null());
    assert_eq!(recorded_error().as_deref(), Some("time zone is null"));
    let tz = cstr("UTC");
    assert!(series_cast_datetime_tz(p, 0, tz.as_ptr()).is_null());
    assert_eq!(recorded_error().as_deref(), Some("unknown time unit"));
    assert!(series_cast_datetime_tz(ptr::null(), US, tz.as_ptr()).is_null());
    assert_eq!(recorded_error().as_deref(), Some("series is null"));
    series_drop(p);
}

#[test]
fn convert_keeps_the_instants_and_treats_naive_as_utc() {
    let instant = utc_us(2021, 3, 27, 3, 0);
    let tz = cstr("Asia/Kathmandu");
    for source in [
        zoned(&[Some(instant), None], "UTC"),
        naive(&[Some(instant), None]),
    ] {
        let p = boxed(source);
        let out = owned(series_dt_convert_time_zone(p, tz.as_ptr()));
        assert_eq!(out.name().as_str(), "t");
        assert_eq!(physical(&out), vec![Some(instant), None]);
        assert_eq!(
            out.dtype(),
            &DataType::Datetime(
                TimeUnit::Microseconds,
                Some(zone("Asia/Kathmandu"))
            )
        );
        series_drop(p);
    }
    let dates = boxed(
        Series::new("d".into(), [1i32])
            .cast(&DataType::Date)
            .unwrap(),
    );
    assert!(series_dt_convert_time_zone(dates, tz.as_ptr()).is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("expected Datetime, got date")
    );
    series_drop(dates);
    let p = boxed(naive(&[Some(0)]));
    let unknown = cstr("Mars/Base");
    assert!(series_dt_convert_time_zone(p, unknown.as_ptr()).is_null());
    assert!(recorded_error()
        .unwrap()
        .contains("unable to parse time zone: 'Mars/Base'"));
    series_drop(p);
}

#[test]
fn replace_keeps_the_wall_clock() {
    let wall = utc_us(2021, 3, 27, 3, 0);
    let utc = zoned(&[Some(wall), None], "UTC");
    let brussels =
        owned(replace(&utc, Some("Europe/Brussels"), "raise", "raise"));
    assert_eq!(physical(&brussels), vec![Some(wall - 3_600_000_000), None]);
    let unset = owned(replace(&brussels, None, "raise", "raise"));
    assert_eq!(
        unset.dtype(),
        &DataType::Datetime(TimeUnit::Microseconds, None)
    );
    assert_eq!(physical(&unset), vec![Some(wall), None]);
}

#[test]
fn replace_resolves_ambiguous_and_non_existent_times() {
    let ambiguous = naive(&[Some(utc_us(2021, 10, 31, 2, 30))]);
    assert!(
        replace(&ambiguous, Some("Europe/Brussels"), "raise", "raise")
            .is_null()
    );
    let reason = recorded_error().unwrap();
    assert!(reason.contains("is ambiguous in time zone 'Europe/Brussels'"));
    for (how, expected) in [
        ("earliest", Some(utc_us(2021, 10, 31, 0, 30))),
        ("latest", Some(utc_us(2021, 10, 31, 1, 30))),
        ("null", None),
    ] {
        let out =
            owned(replace(&ambiguous, Some("Europe/Brussels"), how, "raise"));
        assert_eq!(physical(&out), vec![expected], "{how}");
    }
    let gap = naive(&[Some(utc_us(2021, 3, 28, 2, 30))]);
    assert!(replace(&gap, Some("Europe/Brussels"), "raise", "raise").is_null());
    assert!(recorded_error()
        .unwrap()
        .contains("is non-existent in time zone 'Europe/Brussels'"));
    let nulled = owned(replace(&gap, Some("Europe/Brussels"), "raise", "null"));
    assert_eq!(physical(&nulled), vec![None]);
    for (a, n, reason) in [
        ("bogus", "raise", "invalid ambiguous Some(\"bogus\")"),
        ("raise", "bogus", "invalid non_existent Some(\"bogus\")"),
    ] {
        assert!(replace(&gap, Some("UTC"), a, n).is_null());
        assert!(recorded_error().unwrap().contains(reason));
    }
    let ints = Series::new("i".into(), [1i64]);
    assert!(replace(&ints, Some("UTC"), "raise", "raise").is_null());
    assert_eq!(
        recorded_error().as_deref(),
        Some("expected Datetime, got i64")
    );
}

#[test]
fn zoned_literal_cast_and_selector() {
    let instant = utc_us(2021, 3, 27, 12, 0);
    let tz = cstr("Europe/Brussels");
    let brussels = DataType::Datetime(
        TimeUnit::Microseconds,
        Some(zone("Europe/Brussels")),
    );
    let literal = take_expr(expr_lit_datetime_tz(instant, US, tz.as_ptr()));
    let out = evaluate(vec![naive(&[Some(0)])], literal.clone()).unwrap();
    assert_eq!(out.dtype(), &brussels);
    assert_eq!(physical(&out), vec![Some(instant)]);

    let frame = vec![
        zoned(&[Some(instant), Some(0)], "Europe/Brussels"),
        naive(&[Some(1), Some(2)]).with_name("n".into()),
    ];
    let later = evaluate(frame.clone(), col("t").gt_eq(literal)).unwrap();
    assert_eq!(
        later.bool().unwrap().iter().collect::<Vec<_>>(),
        vec![Some(true), Some(false)]
    );
    let n = column("n");
    let cast = take_expr(expr_cast_datetime_tz(n, US, tz.as_ptr()));
    let cast = evaluate(frame.clone(), cast).unwrap();
    assert_eq!(cast.dtype(), &brussels);
    assert_eq!(physical(&cast), vec![Some(1), Some(2)]);

    let selected = take_expr(expr_dtype_col_datetime_tz(US, tz.as_ptr()));
    let df = DataFrame::new_infer_height(
        frame.into_iter().map(Column::from).collect(),
    )
    .unwrap()
    .lazy()
    .select([selected])
    .collect()
    .unwrap();
    assert_eq!(df.get_column_names(), vec!["t"]);

    let unknown = cstr("Mars/Base");
    assert!(expr_lit_datetime_tz(0, US, unknown.as_ptr()).is_null());
    assert!(recorded_error().unwrap().contains("'Mars/Base'"));
    assert!(expr_dtype_col_datetime_tz(US, unknown.as_ptr()).is_null());
    assert!(recorded_error().unwrap().contains("'Mars/Base'"));
    assert!(expr_cast_datetime_tz(n, US, unknown.as_ptr()).is_null());
    assert!(recorded_error().unwrap().contains("'Mars/Base'"));
    expr_drop(n);
}

#[test]
fn expression_convert_and_replace() {
    let wall = utc_us(2021, 3, 27, 3, 0);
    let frame = vec![zoned(&[Some(wall)], "UTC")];
    let kathmandu = cstr("Asia/Kathmandu");
    let t = column("t");
    let converted = take_expr(expr_dt_convert_time_zone(t, kathmandu.as_ptr()));
    let converted = evaluate(frame.clone(), converted).unwrap();
    assert_eq!(physical(&converted), vec![Some(wall)]);
    let (raise, null) = (cstr("raise"), cstr("null"));
    let brussels = cstr("Europe/Brussels");
    let replaced = take_expr(expr_dt_replace_time_zone(
        t,
        brussels.as_ptr(),
        raise.as_ptr(),
        raise.as_ptr(),
    ));
    let replaced = evaluate(frame.clone(), replaced).unwrap();
    assert_eq!(physical(&replaced), vec![Some(wall - 3_600_000_000)]);
    let unset = take_expr(expr_dt_replace_time_zone(
        t,
        ptr::null(),
        raise.as_ptr(),
        raise.as_ptr(),
    ));
    let unset = evaluate(frame.clone(), unset).unwrap();
    assert_eq!(
        unset.dtype(),
        &DataType::Datetime(TimeUnit::Microseconds, None)
    );

    let ambiguous = vec![naive(&[Some(utc_us(2021, 10, 31, 2, 30))])];
    let raising = take_expr(expr_dt_replace_time_zone(
        t,
        brussels.as_ptr(),
        raise.as_ptr(),
        raise.as_ptr(),
    ));
    let err = evaluate(ambiguous.clone(), raising)
        .unwrap_err()
        .to_string();
    assert!(err.contains("is ambiguous"), "{err}");
    let nulling = take_expr(expr_dt_replace_time_zone(
        t,
        brussels.as_ptr(),
        null.as_ptr(),
        raise.as_ptr(),
    ));
    assert_eq!(physical(&evaluate(ambiguous, nulling).unwrap()), vec![None]);

    let bogus = cstr("bogus");
    assert!(expr_dt_replace_time_zone(
        t,
        brussels.as_ptr(),
        bogus.as_ptr(),
        raise.as_ptr()
    )
    .is_null());
    assert!(recorded_error().unwrap().contains("invalid ambiguous"));
    let unknown = cstr("Mars/Base");
    assert!(expr_dt_convert_time_zone(t, unknown.as_ptr()).is_null());
    assert!(recorded_error().unwrap().contains("'Mars/Base'"));
    expr_drop(t);
}

#[test]
fn an_offset_parses_to_utc() {
    let data = Series::new(
        "s".into(),
        [
            "2021-03-27T00:00:00+0100",
            "2021-03-28T00:00:00+0100",
            "2021-03-29T00:00:00+0200",
        ],
    );
    let instants = vec![
        Some(utc_us(2021, 3, 26, 23, 0)),
        Some(utc_us(2021, 3, 27, 23, 0)),
        Some(utc_us(2021, 3, 28, 22, 0)),
    ];
    let format = cstr("%Y-%m-%dT%H:%M:%S%z");
    let s = column("s");
    let parsed =
        take_expr(expr_str_to_datetime(s, format.as_ptr(), 1, US, 1, 1, 1));
    let out = evaluate(vec![data.clone()], parsed).unwrap();
    assert_eq!(
        out.dtype(),
        &DataType::Datetime(TimeUnit::Microseconds, Some(zone("UTC")))
    );
    assert_eq!(physical(&out), instants);

    let inferred =
        take_expr(expr_str_to_datetime(s, ptr::null(), 0, US, 1, 1, 1));
    let err = evaluate(vec![data.clone()], inferred)
        .unwrap_err()
        .to_string();
    assert!(err.contains("a time zone is part of the data"), "{err}");

    let (tokyo, raise) = (cstr("Asia/Tokyo"), cstr("raise"));
    for (format, has_format) in [(format.as_ptr(), 1), (ptr::null(), 0)] {
        let parsed = take_expr(expr_str_to_datetime_tz(
            s,
            format,
            has_format,
            US,
            tokyo.as_ptr(),
            raise.as_ptr(),
            1,
            1,
            1,
        ));
        let out = evaluate(vec![data.clone()], parsed).unwrap();
        assert_eq!(
            out.dtype(),
            &DataType::Datetime(
                TimeUnit::Microseconds,
                Some(zone("Asia/Tokyo"))
            )
        );
        assert_eq!(physical(&out), instants);
    }
    expr_drop(s);
}

#[test]
fn a_naive_string_parses_into_a_zone() {
    let data =
        Series::new("s".into(), ["2021-03-27 03:00", "2021-10-31 02:30"]);
    let s = column("s");
    let brussels = cstr("Europe/Brussels");
    let parse = |ambiguous: &str, strict: u8| {
        let a = cstr(ambiguous);
        let e = expr_str_to_datetime_tz(
            s,
            ptr::null(),
            0,
            US,
            brussels.as_ptr(),
            a.as_ptr(),
            strict,
            1,
            1,
        );
        evaluate(vec![data.clone()], take_expr(e))
    };
    let earliest = parse("earliest", 1).unwrap();
    assert_eq!(
        physical(&earliest),
        vec![
            Some(utc_us(2021, 3, 27, 2, 0)),
            Some(utc_us(2021, 10, 31, 0, 30))
        ]
    );
    let err = parse("raise", 1).unwrap_err().to_string();
    assert!(err.contains("is ambiguous"), "{err}");
    let nulled = parse("null", 0).unwrap();
    assert_eq!(
        physical(&nulled),
        vec![Some(utc_us(2021, 3, 27, 2, 0)), None]
    );

    let (unknown, bogus, raise) =
        (cstr("Mars/Base"), cstr("bogus"), cstr("raise"));
    assert!(expr_str_to_datetime_tz(
        s,
        ptr::null(),
        0,
        US,
        unknown.as_ptr(),
        raise.as_ptr(),
        1,
        1,
        1
    )
    .is_null());
    assert!(recorded_error().unwrap().contains("'Mars/Base'"));
    assert!(expr_str_to_datetime_tz(
        s,
        ptr::null(),
        0,
        US,
        brussels.as_ptr(),
        bogus.as_ptr(),
        1,
        1,
        1
    )
    .is_null());
    assert!(recorded_error().unwrap().contains("invalid ambiguous"));
    expr_drop(s);
}

#[test]
fn csv_writes_the_local_time_and_its_offset() {
    let s = zoned(
        &[
            Some(utc_us(2021, 3, 27, 11, 0) + 500_000),
            None,
            Some(utc_us(2021, 6, 30, 22, 0)),
        ],
        "Europe/Brussels",
    );
    let df = make_df(&[boxed(s)]);
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t.csv");
    let p = cstr(path.to_str().unwrap());
    assert_eq!(dataframe_write_csv(df, p.as_ptr()), 0);
    assert_eq!(
        std::fs::read_to_string(&path).unwrap(),
        "t\n2021-03-27T12:00:00.500000+0100\n\n2021-07-01T00:00:00.000000+0200\n"
    );
    dataframe_drop(df);
}

#[test]
fn parquet_keeps_the_zone() {
    let s = zoned(&[Some(utc_us(2021, 3, 27, 11, 0))], "Asia/Kathmandu");
    let df = make_df(&[boxed(s)]);
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t.parquet");
    let p = cstr(path.to_str().unwrap());
    assert_eq!(dataframe_write_parquet(df, p.as_ptr()), 0);
    let back = dataframe_read_parquet(p.as_ptr());
    assert!(!back.is_null(), "{:?}", recorded_error());
    let t = unsafe { (*back).column("t").unwrap().dtype().clone() };
    assert_eq!(
        t,
        DataType::Datetime(
            TimeUnit::Microseconds,
            Some(zone("Asia/Kathmandu"))
        )
    );
    dataframe_drop(df);
    dataframe_drop(back);
}
