use super::test_util::*;
use super::*;

const VALUES: [i32; 5] = [1, 2, 3, 4, 5];

const COUNTS: [usize; 4] = [
    u32::MAX as usize + 1,
    u32::MAX as usize + 2,
    i64::MAX as usize + 1,
    usize::MAX,
];

struct Owned<T>(*mut T, extern "C" fn(*mut T));

impl<T> Owned<T> {
    fn new(p: *mut T, drop: extern "C" fn(*mut T)) -> Self {
        assert!(!p.is_null(), "{:?}", recorded_error());
        Owned(p, drop)
    }
}

impl<T> Drop for Owned<T> {
    fn drop(&mut self) {
        (self.1)(self.0)
    }
}

fn kept(from: usize, to: usize) -> Vec<Option<i32>> {
    VALUES[from..to].iter().copied().map(Some).collect()
}

fn collected(
    build: impl FnOnce(*mut LazyFrame) -> *mut LazyFrame,
) -> Vec<Option<i32>> {
    let frame =
        DataFrame::new_infer_height(vec![Column::new("x".into(), VALUES)])
            .unwrap();
    let df = Owned::new(Box::into_raw(Box::new(frame)), dataframe_drop);
    let lf = Owned::new(dataframe_lazy(df.0), lazyframe_drop);
    let built = Owned::new(build(lf.0), lazyframe_drop);
    let out = Owned::new(lazyframe_collect(built.0), dataframe_drop);
    unsafe { (*out.0).column("x").unwrap().i32().unwrap().to_vec() }
}

fn selected(build: impl FnOnce(*const Expr) -> *mut Expr) -> Vec<Option<i32>> {
    let name = cstr("x");
    let x = Owned::new(expr_col(name.as_ptr()), expr_drop);
    let e = Owned::new(build(x.0), expr_drop);
    collected(|lf| {
        let exprs: [*const Expr; 1] = [e.0];
        lazyframe_select(lf, exprs.as_ptr(), 1)
    })
}

#[test]
fn a_count_past_the_index_type_saturates() {
    let cases: [(&str, fn(usize) -> Vec<Option<i32>>, usize); 7] = [
        (
            "lazyframe_head",
            |n| collected(|lf| lazyframe_head(lf, n)),
            0,
        ),
        (
            "lazyframe_tail",
            |n| collected(|lf| lazyframe_tail(lf, n)),
            0,
        ),
        (
            "lazyframe_slice 1",
            |n| collected(|lf| lazyframe_slice(lf, 1, n)),
            1,
        ),
        (
            "lazyframe_slice -2",
            |n| collected(|lf| lazyframe_slice(lf, -2, n)),
            3,
        ),
        ("expr_head", |n| selected(|x| expr_head(x, 1, n)), 0),
        ("expr_tail", |n| selected(|x| expr_tail(x, 1, n)), 0),
        (
            "expr_slice_v2 1",
            |n| selected(|x| expr_slice_v2(x, 1, n)),
            1,
        ),
    ];
    for (name, rows, from) in cases {
        for n in COUNTS {
            assert_eq!(rows(n), kept(from, VALUES.len()), "{name} {n}");
        }
    }
}

const OFFSET_WINDOWS: [(i64, usize, usize, usize); 5] = [
    (-(1 << 33), (1 << 33) + 2, 0, 5),
    (-(1 << 33), (1 << 33) - 2, 0, 3),
    (-(1 << 33), 1 << 32, 0, 0),
    (i64::MIN, usize::MAX, 0, 5),
    (i64::MIN, (1 << 63) - 4, 0, 1),
];

#[test]
fn expr_slice_v2_keeps_the_window_of_any_offset_and_length() {
    for (offset, length, from, to) in OFFSET_WINDOWS {
        assert_eq!(
            selected(|x| expr_slice_v2(x, offset, length)),
            kept(from, to),
            "{offset} {length}"
        );
    }
}

#[test]
fn lazyframe_slice_keeps_the_window_of_an_offset_past_the_index_type() {
    for (offset, length, from, to) in OFFSET_WINDOWS {
        assert_eq!(
            collected(|lf| lazyframe_slice(lf, offset, length)),
            kept(from, to),
            "{offset} {length}"
        );
    }
}
