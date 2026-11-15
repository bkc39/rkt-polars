use super::test_util::*;
use super::*;

fn frame() -> (*mut DataFrame, [*mut Series; 2]) {
    let a = make_opt_i32("a", &[Some(1), None, Some(1), None]);
    let b = make_opt_i32("b", &[None, Some(2), Some(3), None]);
    (make_df(&[a, b]), [a, b])
}

fn release(df: *mut DataFrame, cols: [*mut Series; 2]) {
    dataframe_drop(df);
    for c in cols {
        series_drop(c);
    }
}

fn collect_plan(lf: *mut LazyFrame) -> *mut DataFrame {
    assert!(!lf.is_null());
    let out = lazyframe_collect(lf);
    lazyframe_drop(lf);
    assert!(!out.is_null(), "{:?}", recorded_error());
    out
}

fn select(df: *mut DataFrame, e: *mut Expr) -> *mut DataFrame {
    let lf = dataframe_lazy(df);
    let exprs: [*const Expr; 1] = [e];
    let out = collect_plan(lazyframe_select(lf, exprs.as_ptr(), 1));
    lazyframe_drop(lf);
    expr_drop(e);
    out
}

#[test]
fn expr_sort_places_nulls_by_flag() {
    let (df, cols) = frame();
    let cases: [(u8, u8, [Option<i32>; 4]); 4] = [
        (0, 0, [None, None, Some(2), Some(3)]),
        (0, 1, [Some(2), Some(3), None, None]),
        (1, 0, [None, None, Some(3), Some(2)]),
        (1, 1, [Some(3), Some(2), None, None]),
    ];
    for (descending, nulls_last, expected) in cases {
        let b = column("b");
        let out = select(df, expr_sort_with_options(b, descending, nulls_last));
        expr_drop(b);
        assert_eq!(read_opt_i32_col(out, "b"), expected.to_vec());
        dataframe_drop(out);
    }
    release(df, cols);
}

#[test]
fn expr_sort_prints_as_the_crate_sort() {
    let cases = [(0, 0, "asc"), (0, 1, "asc"), (1, 0, "desc"), (1, 1, "desc")];
    for (descending, nulls_last, order) in cases {
        let b = column("b");
        let sorted = expr_sort_with_options(b, descending, nulls_last);
        assert_eq!(
            take_str(expr_to_string_v2(sorted)),
            format!("col(\"b\").sort({order})")
        );
        expr_drop(sorted);
        expr_drop(b);
    }
}

/// `expr_sort_with_options` is the crate's sort of `e` under every flag.
fn assert_crate_sort(e: *const Expr) {
    for (descending, nulls_last) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
        let sorted = expr_sort_with_options(e, descending, nulls_last);
        assert!(!sorted.is_null());
        let (input, out) = unsafe { (&*e, &*sorted) };
        let Expr::Sort { expr, options } = out else {
            panic!("unexpected sort of {input}: {out}");
        };
        assert_eq!(**expr, *input);
        assert_eq!(
            (options.descending, options.nulls_last),
            (descending != 0, nulls_last != 0)
        );
        expr_drop(sorted);
    }
}

fn boxed(e: Expr) -> *mut Expr {
    Box::into_raw(Box::new(e))
}

fn float64() -> CompatDType {
    CompatDType {
        tag: CompatDTypeTag::Float64 as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    }
}

fn when(
    predicate: *const Expr,
    then: *const Expr,
    otherwise: *const Expr,
) -> *mut Expr {
    let out =
        expr_when_then([predicate].as_ptr(), [then].as_ptr(), 1, otherwise);
    assert!(!out.is_null());
    out
}

#[test]
fn expr_sort_is_the_crate_sort_of_any_input() {
    let (v, s, g) = (column("v"), column("s"), column("g"));
    let total = expr_sum(v);
    let first = expr_first(s);
    let one = expr_lit_i32(1);
    let word = str_block("x");
    let magnitude = expr_abs(total);
    let above = expr_gt(total, one);
    let row_above = expr_gt(v, one);
    let parts: [*const Expr; 1] = [g];
    let cases = [
        aliased(total, "s"),
        expr_lit_str_v2(word.as_ptr()),
        expr_add(total, one),
        expr_div(total, one),
        boxed(len()),
        expr_cast(total, float64()),
        when(above, total, one),
        boxed(col("v").sum().name().keep()),
        column("^v.*$"),
        expr_all(),
        aliased(v, "w"),
        expr_cast(v, float64()),
        expr_sort_with_options(v, 1, 0),
        expr_add(v, total),
        expr_div(v, total),
        when(row_above, total, one),
        when(above, v, one),
        boxed(col("v").name().keep()),
        expr_neg(total),
        expr_str_to_uppercase(first),
        expr_reverse(total),
        expr_cum_sum(total, 0),
        expr_div(magnitude, one),
        expr_head(v, 1, 2),
        expr_filter(v, row_above),
        expr_over(total, parts.as_ptr(), 1),
    ];
    for e in cases
        .iter()
        .copied()
        .chain([magnitude, total, one, first, v])
    {
        assert_crate_sort(e);
    }
    for e in cases
        .into_iter()
        .chain([row_above, above, magnitude, one, first, total, g, s, v])
    {
        expr_drop(e);
    }
}

/// A thousand rows in two groups, "a" with two and "b" with the rest, so a
/// gather of group "b"'s row indices from one value per group reads far out
/// of bounds. The words are too long to be inlined in their string views.
fn words() -> (*mut DataFrame, [*mut Series; 3]) {
    let groups: Vec<&str> =
        (0..1000).map(|i| if i < 2 { "a" } else { "b" }).collect();
    let words: Vec<String> =
        (0..1000).map(|i| format!("word number {i:04}")).collect();
    let words: Vec<&str> = words.iter().map(String::as_str).collect();
    let values: Vec<i64> = (0..1000).map(|i| -i).collect();
    let cols = [
        make_str("g", &groups),
        make_str("s", &words),
        make_i64("v", &values),
    ];
    (make_df(&cols), cols)
}

fn agg_by_g(df: *mut DataFrame, e: *mut Expr) -> *mut DataFrame {
    let key = column("g");
    let named = aliased(e, "x");
    let keys: [*const Expr; 1] = [key];
    let aggs: [*const Expr; 1] = [named];
    let lf = dataframe_lazy(df);
    let grouped =
        lazyframe_group_by_agg(lf, keys.as_ptr(), 1, aggs.as_ptr(), 1);
    let by = str_list_block(&["g"]);
    let out = collect_plan(lazyframe_sort_with_options_v2(
        grouped,
        by.as_ptr(),
        [0].as_ptr(),
        [0].as_ptr(),
        1,
        0,
    ));
    lazyframe_drop(grouped);
    lazyframe_drop(lf);
    for e in [named, key, e] {
        expr_drop(e);
    }
    out
}

fn over_g(df: *mut DataFrame, e: *mut Expr) -> *mut DataFrame {
    let key = column("g");
    let parts: [*const Expr; 1] = [key];
    let windowed = expr_over(e, parts.as_ptr(), 1);
    let out = select(df, aliased(windowed, "x"));
    for e in [windowed, key, e] {
        expr_drop(e);
    }
    out
}

fn i64_lists(df: *mut DataFrame) -> Vec<Vec<Option<i64>>> {
    let lists = unsafe { &*df }.column("x").unwrap().list().unwrap().clone();
    (0..lists.len())
        .map(|i| lists.get_as_series(i).unwrap().i64().unwrap().to_vec())
        .collect()
}

fn sort_of(build: fn() -> *mut Expr, flags: (u8, u8)) -> *mut Expr {
    let e = build();
    let sorted = expr_sort_with_options(e, flags.0, flags.1);
    expr_drop(e);
    sorted
}

#[test]
fn expr_sort_of_one_value_per_group_stays_in_bounds() {
    let (df, cols) = words();
    let upper: fn() -> *mut Expr =
        || boxed(col("s").first().str().to_uppercase());
    let first: fn() -> *mut Expr = || boxed(col("s").first());
    let magnitude: fn() -> *mut Expr = || boxed(col("v").sum().abs());
    let count: fn() -> *mut Expr = || boxed(len());
    let seven: fn() -> *mut Expr = || boxed(lit(7i64));
    let filtered: fn() -> *mut Expr =
        || boxed(col("v").filter(col("v").lt(lit(-500i64))).sum());
    for flags in [(0, 0), (0, 1), (1, 0), (1, 1)] {
        for (build, expected) in [
            (upper, ["WORD NUMBER 0000", "WORD NUMBER 0002"]),
            (first, ["word number 0000", "word number 0002"]),
        ] {
            let out = agg_by_g(df, sort_of(build, flags));
            assert_eq!(read_str_col(out, "x"), expected);
            dataframe_drop(out);
            let out = over_g(df, sort_of(build, flags));
            let x = read_str_col(out, "x");
            assert_eq!(x.len(), 1000);
            assert_eq!(x[..2], [expected[0], expected[0]]);
            assert!(x[2..].iter().all(|w| w == expected[1]));
            dataframe_drop(out);
        }
        let out = agg_by_g(df, sort_of(magnitude, flags));
        assert_eq!(read_i64_col(out, "x"), [1, 499499]);
        dataframe_drop(out);
        let out = over_g(df, sort_of(magnitude, flags));
        let x = read_i64_col(out, "x");
        assert_eq!(x[..3], [1, 1, 499499]);
        dataframe_drop(out);
        for build in [count, seven, filtered] {
            let out = agg_by_g(df, sort_of(build, flags));
            assert_same_frame(out, agg_by_g(df, build()));
            let out = over_g(df, sort_of(build, flags));
            assert_same_frame(out, over_g(df, build()));
        }
    }
    dataframe_drop(df);
    for c in cols {
        series_drop(c);
    }
}

fn assert_same_frame(out: *mut DataFrame, expected: *mut DataFrame) {
    let (a, b) = unsafe { (&*out, &*expected) };
    assert!(a.equals_missing(b), "{a} against {b}");
    dataframe_drop(out);
    dataframe_drop(expected);
}

#[test]
fn expr_sort_of_a_per_row_input_sorts_each_group() {
    let (df, cols) = words();
    let shifted: fn() -> *mut Expr = || boxed(col("v") + col("v").sum());
    let out = agg_by_g(df, sort_of(shifted, (1, 1)));
    let [a, b] = &i64_lists(out)[..] else {
        panic!("expected two groups");
    };
    assert_eq!(a, &[Some(-1), Some(-2)]);
    assert_eq!(b.len(), 998);
    assert_eq!((b[0], b[997]), (Some(-499501), Some(-500498)));
    dataframe_drop(out);
    let shares = || {
        let v = boxed(col("v"));
        let total = boxed(col("v").sum());
        let out = expr_div(v, total);
        expr_drop(total);
        expr_drop(v);
        out
    };
    let out = agg_by_g(df, sort_of(shares, (1, 1)));
    let [a, b] = &i64_lists(out)[..] else {
        panic!("expected two groups");
    };
    assert_eq!(a, &[Some(1), Some(0)]);
    assert_eq!(b.len(), 998);
    dataframe_drop(out);
    dataframe_drop(df);
    for c in cols {
        series_drop(c);
    }
}

#[test]
fn expr_sort_by_places_nulls_per_key() {
    let (df, cols) = frame();
    let (a, b) = (column("a"), column("b"));
    let by: [*const Expr; 2] = [a, b];
    let sorted = expr_sort_by_with_options(
        b,
        by.as_ptr(),
        [0, 0].as_ptr(),
        [1, 0].as_ptr(),
        2,
        1,
    );
    assert!(!sorted.is_null());
    let out = select(df, sorted);
    assert_eq!(
        read_opt_i32_col(out, "b"),
        vec![None, Some(3), None, Some(2)]
    );
    dataframe_drop(out);
    expr_drop(a);
    expr_drop(b);
    release(df, cols);
}

#[test]
fn expr_sort_by_without_keys_returns_null() {
    let b = column("b");
    let by: [*const Expr; 0] = [];
    assert!(expr_sort_by_with_options(
        b,
        by.as_ptr(),
        ptr::null(),
        ptr::null(),
        0,
        0
    )
    .is_null());
    expr_drop(b);
}

#[test]
fn lazyframe_sort_places_nulls_per_key() {
    let (df, cols) = frame();
    let names = str_list_block(&["a", "b"]);
    let lf = dataframe_lazy(df);
    let sorted = lazyframe_sort_with_options_v2(
        lf,
        names.as_ptr(),
        [0, 1].as_ptr(),
        [1, 1].as_ptr(),
        2,
        1,
    );
    lazyframe_drop(lf);
    let out = collect_plan(sorted);
    assert_eq!(
        read_opt_i32_col(out, "a"),
        vec![Some(1), Some(1), None, None]
    );
    assert_eq!(
        read_opt_i32_col(out, "b"),
        vec![Some(3), None, Some(2), None]
    );
    dataframe_drop(out);
    release(df, cols);
}

#[test]
fn expr_sort_of_booleans_places_nulls_by_flag() {
    let (t, f) = (Some(true), Some(false));
    let b = make_opt_bool("b", &[t, None, f, t]);
    let df = make_df(&[b]);
    let cases = [
        (0, 1, [f, t, t, None]),
        (1, 0, [None, t, t, f]),
        (1, 1, [t, t, f, None]),
    ];
    for (descending, nulls_last, expected) in cases {
        let e = column("b");
        let out = select(df, expr_sort_with_options(e, descending, nulls_last));
        expr_drop(e);
        assert_eq!(read_opt_bool_col(out, "b"), expected.to_vec());
        dataframe_drop(out);
    }
    dataframe_drop(df);
    series_drop(b);
}

#[test]
fn expr_sort_of_a_sorted_column_honours_nulls_last() {
    let x = make_opt_i32("x", &[Some(3), None, Some(1), None, Some(2)]);
    let df = make_df(&[x]);
    let names = str_list_block(&["x"]);
    let lf = dataframe_lazy(df);
    let once = collect_plan(lazyframe_sort_with_options_v2(
        lf,
        names.as_ptr(),
        [0].as_ptr(),
        [0].as_ptr(),
        1,
        0,
    ));
    lazyframe_drop(lf);
    let e = column("x");
    let out = select(once, expr_sort_with_options(e, 0, 1));
    expr_drop(e);
    assert_eq!(
        read_opt_i32_col(out, "x"),
        vec![Some(1), Some(2), Some(3), None, None]
    );
    for p in [out, once, df] {
        dataframe_drop(p);
    }
    series_drop(x);
}

#[test]
fn lazy_sort_then_projection_handles_booleans() {
    let a = make_i32("a", &[2, 1, 2]);
    let b = make_opt_bool("b", &[Some(true), None, Some(false)]);
    let df = make_df(&[a, b]);
    let names = str_list_block(&["b"]);
    let lf = dataframe_lazy(df);
    let sorted = lazyframe_sort_with_options_v2(
        lf,
        names.as_ptr(),
        [0].as_ptr(),
        [1].as_ptr(),
        1,
        0,
    );
    let e = column("b");
    let exprs: [*const Expr; 1] = [e];
    let out = collect_plan(lazyframe_select(sorted, exprs.as_ptr(), 1));
    assert_eq!(
        read_opt_bool_col(out, "b"),
        vec![Some(false), Some(true), None]
    );
    expr_drop(e);
    lazyframe_drop(sorted);
    lazyframe_drop(lf);
    dataframe_drop(out);
    dataframe_drop(df);
    series_drop(a);
    series_drop(b);
}
