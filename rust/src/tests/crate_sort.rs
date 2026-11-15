use super::*;
use polars::series::IsSorted;

fn bools() -> Series {
    Series::new("b".into(), [Some(true), None, Some(false)])
}

fn opts(descending: bool, nulls_last: bool) -> SortOptions {
    SortOptions::default()
        .with_order_descending(descending)
        .with_nulls_last(nulls_last)
}

fn bool_values(s: &Series) -> Vec<Option<bool>> {
    s.bool().unwrap().iter().collect()
}

fn i64_values(s: &Series) -> Vec<Option<i64>> {
    s.i64().unwrap().iter().collect()
}

#[test]
fn sort_with_puts_boolean_nulls_last_without_panicking() {
    let s = bools();
    let ascending = s.sort_with(opts(false, true)).unwrap();
    assert_eq!(bool_values(&ascending), [Some(false), Some(true), None]);
    let descending = s.sort_with(opts(true, true)).unwrap();
    assert_eq!(bool_values(&descending), [Some(true), Some(false), None]);
}

#[test]
fn sort_with_keeps_boolean_nulls_first_when_descending() {
    let sorted = bools().sort_with(opts(true, false)).unwrap();
    assert_eq!(bool_values(&sorted), [None, Some(true), Some(false)]);
}

#[test]
fn sort_with_moves_nulls_of_a_column_flagged_sorted() {
    let mut s = Series::new("x".into(), [None, Some(1i64), Some(2), Some(3)]);
    s.set_sorted_flag(IsSorted::Ascending);
    let sorted = s.sort_with(opts(false, true)).unwrap();
    assert_eq!(i64_values(&sorted), [Some(1), Some(2), Some(3), None]);
}

#[test]
fn arg_sort_of_the_null_dtype_is_all_ties() {
    let nulls = Series::full_null("n".into(), 3, &DataType::Null);
    let idx = nulls.arg_sort(SortOptions::default());
    assert_eq!(idx.iter().collect::<Vec<_>>(), [Some(0), Some(1), Some(2)]);
    let df = DataFrame::new_infer_height(vec![
        nulls.into_column(),
        Column::new("v".into(), [3i64, 1, 2]),
    ])
    .unwrap();
    let sorted = df
        .sort(
            ["n"],
            SortMultipleOptions::default().with_maintain_order(true),
        )
        .unwrap();
    assert_eq!(
        i64_values(sorted.column("v").unwrap().as_materialized_series()),
        [Some(3), Some(1), Some(2)]
    );
}

#[test]
fn sort_by_keeps_nulls_last_on_regrouped_input() {
    let df = DataFrame::new_infer_height(vec![
        Column::new("k".into(), ["a", "a", "a", "b", "b"]),
        Column::new("x".into(), [1i64, 2, 3, 4, 5]),
    ])
    .unwrap();
    let shifted = col("x").shift(lit(1));
    let sorted = shifted.clone().sort_by(
        [shifted],
        SortMultipleOptions::default().with_nulls_last(true),
    );
    let grouped = df
        .clone()
        .lazy()
        .group_by_stable([col("k")])
        .agg([sorted.clone().alias("x")])
        .collect()
        .unwrap();
    let flat = grouped
        .column("x")
        .unwrap()
        .as_materialized_series()
        .explode(ExplodeOptions {
            empty_as_null: true,
            keep_nulls: true,
        })
        .unwrap();
    assert_eq!(i64_values(&flat), [Some(1), Some(2), None, Some(4), None]);
    let windowed = df
        .lazy()
        .select([sorted.over([col("k")]).unwrap()])
        .collect()
        .unwrap();
    assert_eq!(
        i64_values(windowed.column("x").unwrap().as_materialized_series()),
        [Some(1), Some(2), None, Some(4), None]
    );
}

/// pola-rs/polars#30325: unsorted keys give index groups, from which the
/// crate's sort gathered one value per group, out of bounds.
fn per_group_queries(df: &DataFrame, e: Expr) -> [DataFrame; 3] {
    let agg = |e: Expr| {
        let grouped = df.clone().lazy().group_by_stable([col("g")]);
        grouped.agg([e.alias("r")]).collect().unwrap()
    };
    let above = when(col("x").gt(lit(2i64)))
        .then(e.clone())
        .otherwise(lit(Null {}));
    let windowed = e.clone().over([col("g")]).unwrap().alias("r");
    [
        agg(e),
        agg(above),
        df.clone().lazy().select([windowed]).collect().unwrap(),
    ]
}

#[test]
fn sort_of_one_value_per_group_is_a_no_op() {
    let x: [Option<i64>; 6] = [Some(3), Some(1), None, None, Some(4), Some(6)];
    let df = DataFrame::new_infer_height(vec![
        Column::new("g".into(), [2i64, 1, 2, 3, 1, 2]),
        Column::new("x".into(), x),
        Column::new("s".into(), ["c", "a", "b", "e", "d", "f"]),
    ])
    .unwrap();
    let inputs = [
        col("x").sum(),
        col("x").max(),
        col("s").min(),
        col("x").filter(col("x").gt(lit(3i64))).sum(),
        len(),
        lit(1i64),
    ];
    for e in inputs {
        let expected = per_group_queries(&df, e.clone());
        for (descending, nulls_last) in [(false, false), (true, true)] {
            let sorted = e.clone().sort(opts(descending, nulls_last));
            let out = per_group_queries(&df, sorted);
            for (out, expected) in out.iter().zip(&expected) {
                assert!(out.equals_missing(expected), "{out} vs {expected}");
            }
        }
    }
}
