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
