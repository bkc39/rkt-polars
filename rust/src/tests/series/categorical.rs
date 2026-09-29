use super::test_util::*;
use super::*;

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

fn names(categories: &[&str]) -> (Vec<CString>, Vec<*const c_char>) {
    let owned: Vec<CString> = categories.iter().map(|c| cstr(c)).collect();
    let ptrs = owned.iter().map(|c| c.as_ptr()).collect();
    (owned, ptrs)
}

fn cast_enum(s: *mut Series, categories: &[&str]) -> *mut Series {
    let (_owned, ptrs) = names(categories);
    series_cast_enum(s, ptrs.as_ptr(), ptrs.len())
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
    let e = expr_col(cstr("s").as_ptr());
    let (_owned, ptrs) = names(&["a", "a"]);
    assert!(expr_cast_enum(e, ptrs.as_ptr(), ptrs.len()).is_null());
    assert!(expr_dtype_col_enum(ptrs.as_ptr(), ptrs.len()).is_null());
    expr_drop(e);
    series_drop(s);
}

#[test]
fn ref_str_reads_categorical_and_enum_values() {
    let s = boxed(strings(&[Some("x"), None, Some("y")]));
    let cat = series_cast(s, categorical_tag());
    let e = cast_enum(s, &["y", "x"]);
    for p in [s, cat, e] {
        assert_eq!(take_cstring(series_ref_str(p, 0)), "x");
        assert!(series_ref_str(p, 1).is_null());
        assert_eq!(take_cstring(series_ref_str(p, 2)), "y");
        series_drop(p);
    }
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
    let (_owned, ptrs) = names(&["debug", "info"]);
    let selector = expr_dtype_col_enum(ptrs.as_ptr(), ptrs.len());
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
