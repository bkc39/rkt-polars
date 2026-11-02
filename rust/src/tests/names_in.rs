use super::test_util::*;
use super::*;

fn frame() -> *mut DataFrame {
    make_df(&[make_i32("g", &[1, 2]), make_i32("x", &[3, 4])])
}

fn assert_refused(name: &str, failed: bool) {
    assert!(failed, "{name} accepted a malformed block");
    assert_eq!(
        recorded_error(),
        Some(StrError::Truncated.to_string()),
        "{name}"
    );
}

#[test]
fn every_v2_refuses_a_malformed_block_with_its_cause() {
    let bad: Vec<u64> = vec![2, 1];
    let bad_list: Vec<u64> = vec![3, 1, 0];
    let (bad, bad_list) = (bad.as_ptr(), bad_list.as_ptr());
    let g = str_block("g");
    let gs = str_list_block(&["g"]);
    let none = str_list_block(&[]);
    let flags = [0u8];
    let (df, other) = (frame(), frame());
    let lazy = || dataframe_lazy(frame());
    let s = make_i32("s", &[1]);
    let e = expr_col_v2(g.as_ptr());
    let rows: Vec<(&str, Box<dyn Fn() -> bool + '_>)> = vec![
        (
            "series_rename_v2",
            Box::new(|| series_rename_v2(s, bad) == -1),
        ),
        (
            "dataframe_rename_v2",
            Box::new(|| dataframe_rename_v2(df, g.as_ptr(), bad).is_null()),
        ),
        (
            "dataframe_column_v2",
            Box::new(|| dataframe_column_v2(df, bad).is_null()),
        ),
        ("expr_col_v2", Box::new(|| expr_col_v2(bad).is_null())),
        (
            "expr_lit_str_v2",
            Box::new(|| expr_lit_str_v2(bad).is_null()),
        ),
        (
            "expr_alias_v2",
            Box::new(|| expr_alias_v2(e, bad).is_null()),
        ),
        (
            "expr_exclude_v2",
            Box::new(|| expr_exclude_v2(e, bad_list).is_null()),
        ),
        (
            "dataframe_select_v2",
            Box::new(|| dataframe_select_v2(df, bad_list).is_null()),
        ),
        (
            "dataframe_drop_columns_v2",
            Box::new(|| dataframe_drop_columns_v2(df, bad_list).is_null()),
        ),
        (
            "dataframe_sort_with_options_v2",
            Box::new(|| {
                dataframe_sort_with_options_v2(
                    df,
                    bad_list,
                    flags.as_ptr(),
                    flags.as_ptr(),
                    1,
                    0,
                )
                .is_null()
            }),
        ),
        (
            "lazyframe_sort_with_options_v2",
            Box::new(|| {
                lazyframe_sort_with_options_v2(
                    lazy(),
                    bad_list,
                    flags.as_ptr(),
                    flags.as_ptr(),
                    1,
                    0,
                )
                .is_null()
            }),
        ),
        (
            "dataframe_group_by_sum_v2",
            Box::new(|| {
                dataframe_group_by_sum_v2(df, gs.as_ptr(), bad_list).is_null()
            }),
        ),
        (
            "dataframe_group_by_mean_v2",
            Box::new(|| {
                dataframe_group_by_mean_v2(df, bad_list, gs.as_ptr()).is_null()
            }),
        ),
        (
            "dataframe_group_by_min_v2",
            Box::new(|| {
                dataframe_group_by_min_v2(df, bad_list, gs.as_ptr()).is_null()
            }),
        ),
        (
            "dataframe_group_by_max_v2",
            Box::new(|| {
                dataframe_group_by_max_v2(df, bad_list, gs.as_ptr()).is_null()
            }),
        ),
        (
            "dataframe_group_by_count_v2",
            Box::new(|| {
                dataframe_group_by_count_v2(df, bad_list, gs.as_ptr()).is_null()
            }),
        ),
        (
            "dataframe_join_v2",
            Box::new(|| {
                dataframe_join_v2(df, other, gs.as_ptr(), bad_list, 0).is_null()
            }),
        ),
        (
            "lazyframe_join_v2",
            Box::new(|| {
                lazyframe_join_v2(lazy(), lazy(), bad_list, gs.as_ptr(), 0)
                    .is_null()
            }),
        ),
        (
            "dataframe_join_asof_v2",
            Box::new(|| {
                dataframe_join_asof_v2(df, other, bad, g.as_ptr(), 0).is_null()
            }),
        ),
        (
            "dataframe_join_asof_options_v2",
            Box::new(|| {
                dataframe_join_asof_options_v2(
                    df,
                    other,
                    g.as_ptr(),
                    g.as_ptr(),
                    0,
                    bad_list,
                    none.as_ptr(),
                    0,
                    0,
                    0.0,
                )
                .is_null()
            }),
        ),
        (
            "dataframe_pivot_v2",
            Box::new(|| {
                dataframe_pivot_v2(df, gs.as_ptr(), bad_list, none.as_ptr(), 0)
                    .is_null()
            }),
        ),
        (
            "dataframe_unpivot_v2",
            Box::new(|| {
                dataframe_unpivot_v2(df, none.as_ptr(), bad_list).is_null()
            }),
        ),
    ];
    assert_eq!(rows.len(), 22);
    for (name, call) in rows {
        assert_refused(name, call());
    }
}
