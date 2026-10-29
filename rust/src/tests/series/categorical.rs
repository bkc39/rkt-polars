use super::test_util::*;
use super::*;
use serde_json::json;

fn boxed(s: Series) -> *mut Series {
    Box::into_raw(Box::new(s))
}

fn owned(p: *mut Series) -> Series {
    assert!(!p.is_null());
    unsafe { *Box::from_raw(p) }
}

fn categorical_tag() -> CompatDType {
    CompatDType {
        tag: CompatDTypeTag::Categorical as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    }
}

fn cast_enum(s: *mut Series, categories: &[&str]) -> *mut Series {
    let block = str_list_block(categories);
    series_cast_enum_v2(s, block.as_ptr())
}

const NUL_CATEGORIES: [&str; 3] = ["c", "a\0b", "\0"];

/// A String series holding a NUL, a null and a plain value, and its
/// categorical and Enum casts.
fn nul_series() -> [*mut Series; 3] {
    let s = boxed(strings(&[Some("a\0b"), None, Some("c")]));
    [
        s,
        series_cast(s, categorical_tag()),
        cast_enum(s, &NUL_CATEGORIES),
    ]
}

fn enum_categories(p: *mut Series) -> Vec<String> {
    owned(series_enum_categories(p))
        .str()
        .unwrap()
        .iter()
        .flatten()
        .map(str::to_owned)
        .collect()
}

fn strings(values: &[Option<&str>]) -> Series {
    Series::new("s".into(), values)
}

fn two_chunks(s: Series) -> Series {
    let mid = s.len() / 2;
    let mut out = s.slice(0, mid);
    out.append(&s.slice(mid as i64, s.len() - mid)).unwrap();
    out
}

fn copy_cat(p: *mut Series, start: usize, count: usize) -> Vec<Option<String>> {
    let mut codes = vec![u32::MAX; count];
    let mut valid = vec![9u8; count];
    let table = owned(series_copy_cat(
        p,
        start,
        count,
        codes.as_mut_ptr(),
        count,
        valid.as_mut_ptr(),
        count,
    ));
    let table: Vec<&str> = table.str().unwrap().iter().flatten().collect();
    codes
        .iter()
        .zip(&valid)
        .map(|(&code, &ok)| (ok == 1).then(|| table[code as usize].to_string()))
        .collect()
}

#[test]
fn categorical_and_enum_report_their_tags() {
    let s = make_str("s", &["b", "a", "b"]);
    let cat = series_cast(s, categorical_tag());
    assert_eq!(series_dtype(cat).tag, CompatDTypeTag::Categorical as i32);
    let e = cast_enum(s, &["a", "b"]);
    assert_eq!(series_dtype(e).tag, CompatDTypeTag::Enum as i32);
    for p in [s, cat, e] {
        series_drop(p);
    }
}

#[test]
fn categorical_tag_lifts_to_the_global_categories() {
    match polars_dtype_from_compat(&categorical_tag()) {
        Some(DataType::Categorical(categories, _)) => {
            assert!(categories.is_global())
        }
        other => panic!("expected a global categorical, got {:?}", other),
    }
}

#[test]
fn decimal_carries_precision_and_scale() {
    let c = compat_dtype_from_polars(&DataType::Decimal(10, 2));
    assert_eq!(
        (c.tag, c.array_width, c.time_unit),
        (CompatDTypeTag::Decimal as i32, 10, 2)
    );
}

#[test]
fn enum_categories_keep_their_declared_order() {
    let s = make_str("level", &["info", "debug"]);
    let e = cast_enum(s, &["debug", "info", "error"]);
    let categories = owned(series_enum_categories(e));
    assert_eq!(categories.name().as_str(), "level");
    assert_eq!(
        categories
            .str()
            .unwrap()
            .iter()
            .flatten()
            .collect::<Vec<_>>(),
        vec!["debug", "info", "error"]
    );
    assert!(series_enum_categories(s).is_null());
    series_drop(s);
    series_drop(e);
}

#[test]
fn an_enum_cast_is_strict_and_names_the_stray_value() {
    let s = make_str("bears", &["Polar", "Shark"]);
    assert!(cast_enum(s, &["Polar", "Panda"]).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("\"Shark\""), "{}", reason);
    series_drop(s);
}

#[test]
fn duplicate_enum_categories_are_refused() {
    let s = make_str("s", &["a"]);
    assert!(cast_enum(s, &["a", "a"]).is_null());
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("duplicate"), "{}", reason);
    let e = expr_col_v2(str_block("s").as_ptr());
    let twice = str_list_block(&["a", "a"]);
    assert!(expr_cast_enum_v2(e, twice.as_ptr()).is_null());
    assert!(expr_dtype_col_enum_v2(twice.as_ptr()).is_null());
    expr_drop(e);
    series_drop(s);
}

#[test]
fn categorical_and_enum_values_keep_a_nul() {
    let [s, cat, e] = nul_series();
    let expected = vec![Some("a\0b".to_string()), None, Some("c".to_string())];
    for p in [cat, e] {
        assert_eq!(copy_cat(p, 0, 3), expected);
    }
    for p in [s, cat, e] {
        series_drop(p);
    }
}

#[test]
fn ref_cat_reads_a_nul_and_a_null() {
    let [s, cat, e] = nul_series();
    for p in [cat, e] {
        assert_eq!(take_str(series_ref_cat(p, 0)), "a\0b");
        assert!(series_ref_cat(p, 1).is_null());
        assert_eq!(take_str(series_ref_cat(p, 2)), "c");
        assert!(series_ref_cat(p, 3).is_null());
    }
    assert!(series_ref_cat(s, 0).is_null());
    assert!(series_ref_cat(ptr::null_mut(), 0).is_null());
    for p in [s, cat, e] {
        series_drop(p);
    }
}

#[test]
fn enum_categories_keep_a_nul() {
    let [s, cat, e] = nul_series();
    assert_eq!(enum_categories(e), NUL_CATEGORIES);
    for p in [s, cat, e] {
        series_drop(p);
    }
}

#[test]
fn an_enum_selector_matches_categories_with_a_nul() {
    let [s, cat, e] = nul_series();
    let other = make_str("other", &["x", "y", "z"]);
    let df = make_df(&[other, e]);
    let categories = str_list_block(&NUL_CATEGORIES);
    let selector = expr_dtype_col_enum_v2(categories.as_ptr());
    assert!(!selector.is_null());
    let exprs = [selector as *const Expr];
    let lf = lazyframe_select(dataframe_lazy(df), exprs.as_ptr(), 1);
    assert_eq!(read_column_names(lazyframe_collect(lf)), vec!["s"]);
    for p in [s, cat, e, other] {
        series_drop(p);
    }
}

#[test]
fn an_enum_cast_expression_keeps_categories_with_a_nul() {
    let [s, cat, e] = nul_series();
    let df = make_df(&[s]);
    let column = expr_col_v2(str_block("s").as_ptr());
    let categories = str_list_block(&NUL_CATEGORIES);
    let cast = expr_cast_enum_v2(column, categories.as_ptr());
    assert!(!cast.is_null());
    let exprs = [cast as *const Expr];
    let out = lazyframe_collect(lazyframe_select(
        dataframe_lazy(df),
        exprs.as_ptr(),
        1,
    ));
    assert!(!out.is_null());
    let column_out = dataframe_column_v2(out, str_block("s").as_ptr());
    assert_eq!(enum_categories(column_out), NUL_CATEGORIES);
    assert_eq!(
        copy_cat(column_out, 0, 3),
        vec![Some("a\0b".to_string()), None, Some("c".to_string())]
    );
    for p in [s, cat, e, column_out] {
        series_drop(p);
    }
    expr_drop(column);
    expr_drop(cast);
}

#[test]
fn a_malformed_category_block_is_a_recorded_reason() {
    let short = [1u64, 0];
    let s = make_str("s", &["a"]);
    let e = expr_col_v2(str_block("s").as_ptr());
    let cause = "a string block is shorter than its header says";
    assert!(series_cast_enum_v2(s, short.as_ptr()).is_null());
    assert_eq!(recorded_error().as_deref(), Some(cause));
    assert!(expr_cast_enum_v2(e, short.as_ptr()).is_null());
    assert_eq!(recorded_error().as_deref(), Some(cause));
    assert!(expr_dtype_col_enum_v2(short.as_ptr()).is_null());
    assert_eq!(recorded_error().as_deref(), Some(cause));
    expr_drop(e);
    series_drop(s);
}

#[test]
fn copy_cat_matches_the_strings_over_chunks_and_slices() {
    let values: Vec<Option<&str>> = (0..20)
        .map(|i| (i % 4 != 1).then_some(["UA", "IAH", "EWR"][i % 3]))
        .collect();
    let source = two_chunks(strings(&values));
    for dtype in [
        DataType::from_categories(Categories::global()),
        DataType::from_frozen_categories(
            FrozenCategories::new(["EWR", "IAH", "UA"]).unwrap(),
        ),
    ] {
        for s in [source.clone(), source.slice(3, 9)] {
            let s = s.cast(&dtype).unwrap();
            let expected: Vec<Option<String>> = s
                .cast(&DataType::String)
                .unwrap()
                .str()
                .unwrap()
                .iter()
                .map(|v| v.map(str::to_string))
                .collect();
            let p = boxed(s);
            let n = expected.len();
            for (start, count) in [(0, n), (2, n - 4), (n, 0)] {
                assert_eq!(
                    copy_cat(p, start, count),
                    expected[start..start + count].to_vec()
                );
            }
            series_drop(p);
        }
    }
}

#[test]
fn copy_cat_refuses_bad_arguments() {
    let s = boxed(strings(&[Some("a"), Some("b")]));
    let cat = series_cast(s, categorical_tag());
    let mut codes = [0u32; 2];
    let mut copy = |p, start, count, dst_len| {
        series_copy_cat(
            p,
            start,
            count,
            codes.as_mut_ptr(),
            dst_len,
            ptr::null_mut(),
            0,
        )
    };
    assert!(copy(s, 0, 2, 2).is_null());
    assert!(copy(cat, 1, 2, 2).is_null());
    assert!(copy(cat, 0, 2, 1).is_null());
    assert!(copy(ptr::null_mut(), 0, 0, 0).is_null());
    let table = copy(cat, 0, 2, 2);
    assert!(!table.is_null());
    for p in [s, cat, table] {
        series_drop(p);
    }
}

#[test]
fn copy_decimal_writes_twos_complement_words() {
    let raw =
        Series::new("d".into(), &[Some(125i64), Some(-350), None, Some(0)]);
    let s = raw
        .cast(&DataType::Int128)
        .unwrap()
        .into_decimal(10, 2)
        .unwrap();
    let p = boxed(s);
    let mut words = vec![7u64; 8];
    let mut valid = vec![9u8; 4];
    let nulls = series_copy_decimal(
        p,
        0,
        4,
        words.as_mut_ptr(),
        8,
        valid.as_mut_ptr(),
        4,
    );
    assert_eq!(nulls, 1);
    assert_eq!(valid, vec![1, 1, 0, 1]);
    let read = |row: usize| {
        (words[2 * row] as u128 | (words[2 * row + 1] as u128) << 64) as i128
    };
    assert_eq!((read(0), read(1), read(3)), (125, -350, 0));
    assert_eq!(
        series_copy_decimal(p, 0, 4, words.as_mut_ptr(), 7, ptr::null_mut(), 0),
        COPY_BAD_ARGUMENTS
    );
    let ints = make_i64("i", &[1]);
    assert_eq!(
        series_copy_decimal(
            ints,
            0,
            1,
            words.as_mut_ptr(),
            2,
            ptr::null_mut(),
            0
        ),
        COPY_WRONG_DTYPE
    );
    series_drop(ints);
    series_drop(p);
}

#[test]
fn enum_dtype_col_selects_the_enum_column() {
    let s = make_str("level", &["info"]);
    let e = cast_enum(s, &["debug", "info"]);
    let other = make_str("other", &["x"]);
    let df = make_df(&[other, e]);
    let categories = str_list_block(&["debug", "info"]);
    let selector = expr_dtype_col_enum_v2(categories.as_ptr());
    assert!(!selector.is_null());
    let lf = dataframe_lazy(df);
    let exprs = [selector as *const Expr];
    let out = lazyframe_collect(lazyframe_select(lf, exprs.as_ptr(), 1));
    assert!(!out.is_null());
    assert_eq!(read_column_names(out), vec!["level"]);
    for p in [s, e, other] {
        series_drop(p);
    }
}

fn enum_of(categories: &[&str]) -> DataType {
    DataType::from_frozen_categories(
        FrozenCategories::new(categories.iter().copied()).unwrap(),
    )
}

fn parsed_payload(reason: &str) -> serde_json::Value {
    match reason.strip_prefix(ENUM_MISSES_TAG) {
        Some(payload) => serde_json::from_str(payload).unwrap(),
        None => panic!("an untagged reason: {}", reason),
    }
}

fn misses_payload(s: &Series, categories: &[&str]) -> serde_json::Value {
    parsed_payload(
        &enum_cast_checked(s, &enum_of(categories))
            .unwrap_err()
            .to_string(),
    )
}

#[test]
fn an_enum_cast_reports_its_misses_from_any_string_source() {
    let s =
        strings(&[Some("TEB"), None, Some("XYZ"), Some("TEB"), Some("EWR")]);
    let cat = s
        .cast(&DataType::from_categories(Categories::global()))
        .unwrap();
    let other = s.cast(&enum_of(&["EWR", "TEB", "XYZ"])).unwrap();
    for source in [&s, &cat, &other] {
        assert_eq!(
            misses_payload(source, &["EWR", "JFK", "LGA"]),
            json!({
                "categories": ["EWR", "JFK", "LGA"],
                "distinct": 2,
                "missing": 3,
                "shown": ["TEB", "XYZ"],
                "total": 4
            })
        );
    }
}

#[test]
fn the_misses_payload_escapes_what_json_must() {
    let s = strings(&[Some("a\0b"), Some("q\"\\"), Some("\u{1f}")]);
    let reason = enum_cast_checked(&s, &enum_of(&["\"", "\\"]))
        .unwrap_err()
        .to_string();
    assert_eq!(
        parsed_payload(&reason),
        json!({
            "categories": ["\"", "\\"],
            "distinct": 3,
            "missing": 3,
            "shown": ["\u{1f}", "a\0b", "q\"\\"],
            "total": 3
        })
    );
    for escaped in [r#"\u001f"#, r#"a\u0000b"#, r#"q\"\\"#] {
        assert!(reason.contains(escaped), "{}", reason);
    }
}

#[test]
fn the_misses_payload_shows_ten_sorted_misses() {
    let values: Vec<String> =
        (0..12).rev().map(|i| format!("v{:02}", i)).collect();
    let shown: Vec<String> = (0..10).map(|i| format!("v{:02}", i)).collect();
    assert_eq!(
        misses_payload(&Series::new("s".into(), &values), &["a"]),
        json!({
            "categories": ["a"],
            "distinct": 12,
            "missing": 12,
            "shown": shown,
            "total": 12
        })
    );
}

#[test]
fn an_enum_cast_without_misses_is_the_strict_cast() {
    let dtype = enum_of(&["EWR", "TEB"]);
    let s = strings(&[Some("TEB"), None, Some("EWR")]);
    let cat = s
        .cast(&DataType::from_categories(Categories::global()))
        .unwrap();
    for source in [&s, &cat] {
        let checked = enum_cast_checked(source, &dtype).unwrap();
        assert!(checked.equals_missing(&source.strict_cast(&dtype).unwrap()));
        assert_eq!(checked.dtype(), &dtype);
        assert_eq!(checked.name(), source.name());
    }
    let bools = Series::new("b".into(), &[true]);
    assert_eq!(
        enum_cast_checked(&bools, &dtype).unwrap_err().to_string(),
        bools.strict_cast(&dtype).unwrap_err().to_string()
    );
}

const ENUM_HINT: &str = "\n\nEnsure that all values in the input column \
    are present in the categories of the enum datatype.";

#[test]
fn a_lazy_enum_cast_is_polars_strict_cast() {
    let s = make_str("o", &["EWR", "LGA"]);
    let df = make_df(&[s]);
    let column = expr_col_v2(str_block("o").as_ptr());
    let categories = str_list_block(&["EWR"]);
    let cast = expr_cast_enum_v2(column, categories.as_ptr());
    assert!(matches!(
        unsafe { &*cast },
        Expr::Cast {
            options: polars::chunked_array::cast::CastOptions::Strict,
            ..
        }
    ));
    let exprs = [cast as *const Expr];
    let lf = lazyframe_select(dataframe_lazy(df), exprs.as_ptr(), 1);
    assert!(lazyframe_collect(lf).is_null());
    assert_eq!(
        recorded_error().unwrap(),
        format!(
            "conversion from `str` to `enum` failed in column 'o' for 1 out \
             of 2 values: [\"LGA\"]{ENUM_HINT}"
        )
    );
    series_drop(s);
    expr_drop(column);
    expr_drop(cast);
}

#[test]
fn the_misses_payload_counts_many_rows_of_few_misses() {
    let values: Vec<&str> = (0..200_000)
        .map(|i| match i % 50_000 {
            0 => "B6",
            1 => "AA",
            _ => "UA",
        })
        .collect();
    assert_eq!(
        misses_payload(&Series::new("s".into(), &values), &["UA"]),
        json!({
            "categories": ["UA"],
            "distinct": 2,
            "missing": 8,
            "shown": ["AA", "B6"],
            "total": 200000
        })
    );
}

fn lazy_enum_cast(name: &str, categories: &[&str]) -> Expr {
    let column = expr_col_v2(str_block(name).as_ptr());
    let block = str_list_block(categories);
    let cast = expr_cast_enum_v2(column, block.as_ptr());
    let out = unsafe { (*cast).clone() };
    expr_drop(column);
    expr_drop(cast);
    out
}

#[test]
fn a_lazy_enum_cast_counts_one_chunk_as_polars_does() {
    let width = 2 * std::thread::available_parallelism().map_or(8, |n| n.get());
    let piece = |values: &[&str]| {
        let columns: Vec<Column> = (0..width)
            .map(|i| Series::new(format!("o{}", i).into(), values).into())
            .collect();
        DataFrame::new(values.len(), columns).unwrap()
    };
    let mut frame = piece(&["EWR", "LGA", "EWR", "JFK"]);
    frame
        .vstack_mut(&piece(&["JFK", "EWR", "TEB", "EWR"]))
        .unwrap();
    assert_eq!(frame.first_col_n_chunks(), 2);
    let misses = ["JFK", "LGA", "TEB"];
    let cast = lazy_enum_cast("o0", &["EWR"]);
    let plans = [
        frame.clone().lazy().select([cast.clone()]),
        frame.clone().lazy().with_columns([cast.clone()]),
        frame.clone().lazy().filter(cast.clone().is_null()),
    ];
    let lead = "conversion from `str` to `enum` failed in column 'o0' for ";
    for plan in plans {
        let reason = plan.collect().unwrap_err().to_string();
        let counts = reason
            .strip_prefix(lead)
            .and_then(|rest| rest.split_once(" values: ["))
            .and_then(|(counts, rest)| {
                let (missing, total) = counts.split_once(" out of ")?;
                let listing = rest.strip_suffix(&format!("]{ENUM_HINT}"))?;
                Some((
                    missing.parse::<usize>().ok()?,
                    total.parse().ok()?,
                    listing,
                ))
            });
        let (missing, total, listing) = counts.expect(&reason);
        assert!(1 <= missing && missing <= total && total <= 8, "{}", reason);
        let shown: Vec<&str> = listing
            .split(", ")
            .map(|v| v.trim_start_matches("… ").trim_matches('"'))
            .collect();
        assert_eq!(shown.len(), missing.min(3), "{}", reason);
        assert!(shown.iter().all(|v| misses.contains(v)), "{}", reason);
    }
}
