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

const FLAGS: [(u8, u8); 4] = [(0, 0), (0, 1), (1, 0), (1, 1)];

fn boxed(e: Expr) -> *mut Expr {
    Box::into_raw(Box::new(e))
}

fn unboxed(e: *mut Expr) -> Expr {
    assert!(!e.is_null());
    let out = unsafe { (*e).clone() };
    expr_drop(e);
    out
}

fn quotient(a: Expr, b: Expr) -> Expr {
    let (a, b) = (boxed(a), boxed(b));
    let out = unboxed(expr_div(a, b));
    expr_drop(a);
    expr_drop(b);
    out
}

fn sort_of(build: fn() -> Expr, descending: u8, nulls_last: u8) -> *mut Expr {
    let e = boxed(build());
    let sorted = expr_sort_with_options(e, descending, nulls_last);
    expr_drop(e);
    sorted
}

fn assert_crate_sort(name: &str, build: fn() -> Expr) {
    let input = build();
    for (descending, nulls_last) in FLAGS {
        let out = unboxed(sort_of(build, descending, nulls_last));
        let Expr::Sort { expr, options } = &out else {
            panic!("{name}: unexpected sort of {input}: {out}");
        };
        assert_eq!(**expr, input, "{name}");
        assert_eq!(
            (options.descending, options.nulls_last),
            (descending != 0, nulls_last != 0),
            "{name}"
        );
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

fn release_words(df: *mut DataFrame, cols: [*mut Series; 3]) {
    dataframe_drop(df);
    for c in cols {
        series_drop(c);
    }
}

type Query = fn(*mut DataFrame, *mut Expr) -> *mut DataFrame;

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

fn agg_by_g_when_v_is_low(df: *mut DataFrame, e: *mut Expr) -> *mut DataFrame {
    let low = when(col("v").lt(lit(-500i64)))
        .then(unboxed(e))
        .otherwise(lit(Null {}));
    agg_by_g(df, boxed(low))
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

fn assert_same_frame(
    name: &str,
    out: *mut DataFrame,
    expected: *mut DataFrame,
) {
    let (a, b) = unsafe { (&*out, &*expected) };
    assert!(a.equals_missing(b), "{name}: {a} against {b}");
    dataframe_drop(out);
    dataframe_drop(expected);
}

#[test]
fn expr_sort_is_the_crate_sort_of_any_input() {
    let cases: [(&str, fn() -> Expr); 31] = [
        ("a column", || col("v")),
        ("a sum", || col("v").sum()),
        ("a first", || col("s").first()),
        ("an integer literal", || lit(1i32)),
        ("a string literal", || lit("x")),
        ("len", len),
        ("abs of a sum", || col("v").sum().abs()),
        ("an aliased sum", || col("v").sum().alias("s")),
        ("a sum plus a literal", || col("v").sum() + lit(1i32)),
        ("a quotient of a sum", || {
            quotient(col("v").sum(), lit(1i32))
        }),
        ("a cast sum", || col("v").sum().cast(DataType::Float64)),
        ("a when over a sum", || {
            when(col("v").sum().gt(lit(1i32)))
                .then(col("v").sum())
                .otherwise(lit(1i32))
        }),
        ("a sum keeping its name", || col("v").sum().name().keep()),
        ("a regex selector", || unboxed(column("^v.*$"))),
        ("every column", || unboxed(expr_all())),
        ("an aliased column", || col("v").alias("w")),
        ("a cast column", || col("v").cast(DataType::Float64)),
        ("a sorted column", || {
            col("v").sort(SortOptions::default().with_order_descending(true))
        }),
        ("a column plus a sum", || col("v") + col("v").sum()),
        ("a column over a sum", || quotient(col("v"), col("v").sum())),
        ("a when on a row predicate", || {
            when(col("v").gt(lit(1i32)))
                .then(col("v").sum())
                .otherwise(lit(1i32))
        }),
        ("a when choosing a column", || {
            when(col("v").sum().gt(lit(1i32)))
                .then(col("v"))
                .otherwise(lit(1i32))
        }),
        ("a column keeping its name", || col("v").name().keep()),
        ("a negated sum", || -col("v").sum()),
        ("an uppercased first", || {
            col("s").first().str().to_uppercase()
        }),
        ("a reversed sum", || col("v").sum().reverse()),
        ("a cumulative sum of a sum", || {
            col("v").sum().cum_sum(false)
        }),
        ("a quotient of abs of a sum", || {
            quotient(col("v").sum().abs(), lit(1i32))
        }),
        ("a head", || col("v").head(Some(2))),
        ("a filter", || col("v").filter(col("v").gt(lit(1i32)))),
        ("a sum over groups", || {
            col("v").sum().over([col("g")]).unwrap()
        }),
    ];
    for (name, build) in cases {
        assert_crate_sort(name, build);
    }
}

#[test]
fn expr_sort_of_one_value_per_group_is_a_no_op() {
    let (df, cols) = words();
    let cases: [(&str, fn() -> Expr); 10] = [
        ("an uppercased first", || {
            col("s").first().str().to_uppercase()
        }),
        ("a first", || col("s").first()),
        ("abs of a sum", || col("v").sum().abs()),
        ("a negated sum", || -col("v").sum()),
        ("a reversed sum", || col("v").sum().reverse()),
        ("a cumulative sum of a sum", || {
            col("v").sum().cum_sum(false)
        }),
        ("a quotient of abs of a sum", || {
            quotient(col("v").sum().abs(), lit(1i64))
        }),
        ("a filtered sum", || {
            col("v").filter(col("v").lt(lit(-500i64))).sum()
        }),
        ("len", len),
        ("a literal", || lit(7i64)),
    ];
    let queries: [Query; 3] = [agg_by_g, agg_by_g_when_v_is_low, over_g];
    for (name, build) in cases {
        for query in queries {
            for (descending, nulls_last) in FLAGS {
                let out = query(df, sort_of(build, descending, nulls_last));
                assert_same_frame(name, out, query(df, boxed(build())));
            }
        }
    }
    release_words(df, cols);
}

#[test]
fn expr_sort_of_a_per_row_input_sorts_each_group() {
    let (df, cols) = words();
    let shifted: fn() -> Expr = || col("v") + col("v").sum();
    let out = agg_by_g(df, sort_of(shifted, 1, 1));
    let [a, b] = &i64_lists(out)[..] else {
        panic!("expected two groups");
    };
    assert_eq!(a, &[Some(-1), Some(-2)]);
    assert_eq!(b.len(), 998);
    assert_eq!((b[0], b[997]), (Some(-499501), Some(-500498)));
    dataframe_drop(out);
    let shares: fn() -> Expr = || quotient(col("v"), col("v").sum());
    let out = agg_by_g(df, sort_of(shares, 1, 1));
    let [a, b] = &i64_lists(out)[..] else {
        panic!("expected two groups");
    };
    assert_eq!(a, &[Some(1), Some(0)]);
    assert_eq!(b.len(), 998);
    dataframe_drop(out);
    release_words(df, cols);
}

#[test]
fn expr_sort_of_a_head_or_filter_sorts_each_group() {
    let (df, cols) = words();
    let cases: [(&str, fn() -> Expr); 2] = [
        ("a head", || col("v").head(Some(1000))),
        ("a filter", || col("v").filter(col("v").gt(lit(-1000i64)))),
    ];
    let group_b: Vec<Option<i64>> = (-999..=-2).map(Some).collect();
    let rows: Vec<i64> = [-1, 0].into_iter().chain(-999..=-2).collect();
    for (name, build) in cases {
        let out = agg_by_g(df, sort_of(build, 0, 0));
        let expected = [vec![Some(-1), Some(0)], group_b.clone()];
        assert_eq!(i64_lists(out), expected, "{name}");
        dataframe_drop(out);
        let out = over_g(df, sort_of(build, 0, 0));
        assert_eq!(read_i64_col(out, "x"), rows, "{name}");
        dataframe_drop(out);
    }
    release_words(df, cols);
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
