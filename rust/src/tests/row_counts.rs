use super::test_util::*;
use super::*;

const COUNTS: [usize; 4] = [
    u32::MAX as usize + 1,
    u32::MAX as usize + 2,
    i64::MAX as usize + 1,
    usize::MAX,
];

fn values() -> Vec<i32> {
    vec![1, 2, 3, 4, 5]
}

fn frame() -> *mut DataFrame {
    let df =
        DataFrame::new_infer_height(vec![Column::new("x".into(), values())])
            .unwrap();
    Box::into_raw(Box::new(df))
}

fn column_of(df: *mut DataFrame) -> Vec<Option<i32>> {
    assert!(!df.is_null(), "{:?}", recorded_error());
    let out = unsafe { (*df).column("x").unwrap().i32().unwrap().to_vec() };
    dataframe_drop(df);
    out
}

fn collected(
    build: impl FnOnce(*mut LazyFrame) -> *mut LazyFrame,
) -> Vec<Option<i32>> {
    let df = frame();
    let lf = dataframe_lazy(df);
    let built = build(lf);
    assert!(!built.is_null());
    let out = lazyframe_collect(built);
    lazyframe_drop(built);
    lazyframe_drop(lf);
    dataframe_drop(df);
    column_of(out)
}

fn selected(build: impl FnOnce(*const Expr) -> *mut Expr) -> Vec<Option<i32>> {
    let name = cstr("x");
    let x = expr_col(name.as_ptr());
    let e = build(x);
    assert!(!e.is_null());
    let collected = collected(|lf| {
        let exprs: [*const Expr; 1] = [e];
        lazyframe_select(lf, exprs.as_ptr(), 1)
    });
    expr_drop(e);
    expr_drop(x);
    collected
}

fn every_row() -> Vec<Option<i32>> {
    values().into_iter().map(Some).collect()
}

#[test]
fn lazyframe_head_saturates_a_count_past_the_index_type() {
    for n in COUNTS {
        assert_eq!(collected(|lf| lazyframe_head(lf, n)), every_row(), "{n}");
    }
}

#[test]
fn lazyframe_tail_saturates_a_count_past_the_index_type() {
    for n in COUNTS {
        assert_eq!(collected(|lf| lazyframe_tail(lf, n)), every_row(), "{n}");
    }
}

#[test]
fn lazyframe_slice_saturates_a_length_past_the_index_type() {
    for n in COUNTS {
        assert_eq!(
            collected(|lf| lazyframe_slice(lf, 1, n)),
            every_row()[1..].to_vec(),
            "{n}"
        );
        assert_eq!(
            collected(|lf| lazyframe_slice(lf, -2, n)),
            every_row()[3..].to_vec(),
            "{n}"
        );
    }
}

#[test]
fn expr_head_keeps_every_row_for_a_huge_count() {
    for n in COUNTS {
        assert_eq!(selected(|x| expr_head(x, 1, n)), every_row(), "{n}");
    }
}

#[test]
fn expr_tail_saturates_a_count_past_i64() {
    for n in COUNTS {
        assert_eq!(selected(|x| expr_tail(x, 1, n)), every_row(), "{n}");
    }
}
