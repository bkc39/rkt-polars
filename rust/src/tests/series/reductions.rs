use super::test_util::*;
use super::*;

trait Parts {
    fn parts(self) -> (i32, f64);
}

macro_rules! reduction_parts {
    ($($opt:ident),+) => {
        $(impl Parts for $opt {
            fn parts(self) -> (i32, f64) {
                (self.valid, self.value as f64)
            }
        })+
    };
}

reduction_parts!(
    CompatOptI8,
    CompatOptI16,
    CompatOptI32,
    CompatOptI64,
    CompatOptU8,
    CompatOptU16,
    CompatOptU32,
    CompatOptU64,
    CompatOptF32,
    CompatOptF64
);

impl Parts for i64 {
    fn parts(self) -> (i32, f64) {
        (if self < 0 { -1 } else { 1 }, self as f64)
    }
}

type Reduction = fn(*const Series) -> (i32, f64);

struct Typed {
    name: &'static str,
    reduce: Reduction,
    dtype: DataType,
    of_one_to_four: f64,
    of_nulls: (i32, f64),
}

macro_rules! typed_reductions {
    ($($dtype:ident: $sum:ident $min:ident $max:ident $mean:ident;)+) => {
        [$(
            typed_reductions!(@row $dtype $sum 10.0, (1, 0.0)),
            typed_reductions!(@row $dtype $min 1.0, (0, 0.0)),
            typed_reductions!(@row $dtype $max 4.0, (0, 0.0)),
            typed_reductions!(@row $dtype $mean 2.5, (0, 0.0)),
        )+]
    };
    (@row $dtype:ident $f:ident $of_one_to_four:expr, $of_nulls:expr) => {
        Typed {
            name: stringify!($f),
            reduce: |s| $f(s).parts(),
            dtype: DataType::$dtype,
            of_one_to_four: $of_one_to_four,
            of_nulls: $of_nulls,
        }
    };
}

const TYPED_REDUCTIONS: [Typed; 40] = typed_reductions! {
    Int8: series_sum_i8_v2 series_min_i8_v2 series_max_i8_v2 series_mean_i8_v2;
    Int16: series_sum_i16_v2 series_min_i16_v2 series_max_i16_v2
        series_mean_i16_v2;
    Int32: series_sum_i32_v2 series_min_i32_v2 series_max_i32_v2
        series_mean_i32_v2;
    Int64: series_sum_i64_v2 series_min_i64_v2 series_max_i64_v2
        series_mean_i64_v2;
    UInt8: series_sum_u8_v2 series_min_u8_v2 series_max_u8_v2 series_mean_u8_v2;
    UInt16: series_sum_u16_v2 series_min_u16_v2 series_max_u16_v2
        series_mean_u16_v2;
    UInt32: series_sum_u32_v2 series_min_u32_v2 series_max_u32_v2
        series_mean_u32_v2;
    UInt64: series_sum_u64_v2 series_min_u64_v2 series_max_u64_v2
        series_mean_u64_v2;
    Float32: series_sum_f32_v2 series_min_f32_v2 series_max_f32_v2
        series_mean_f32_v2;
    Float64: series_sum_f64_v2 series_min_f64_v2 series_max_f64_v2
        series_mean_f64_v2;
};

const OTHER_REDUCTIONS: [(&str, Reduction); 4] = [
    ("series_n_unique_v2", |s| series_n_unique_v2(s).parts()),
    ("series_std_v2", |s| series_std_v2(s, 1).parts()),
    ("series_var_v2", |s| series_var_v2(s, 1).parts()),
    ("series_quantile_v2", |s| {
        series_quantile_v2(s, 0.5, 0).parts()
    }),
];

fn one_to_four(name: &str, dtype: &DataType) -> *mut Series {
    boxed(
        Series::new(name.into(), &[1i64, 2, 3, 4])
            .cast(dtype)
            .unwrap(),
    )
}

#[test]
fn typed_reductions_reduce_their_dtype() {
    for Typed {
        name,
        reduce,
        dtype,
        of_one_to_four,
        ..
    } in TYPED_REDUCTIONS
    {
        let s = one_to_four("xs", &dtype);
        clear_last_error();
        assert_eq!(reduce(s), (1, of_one_to_four), "{}", name);
        assert_eq!(recorded_error(), None, "{}", name);
        series_drop(s);
    }
}

#[test]
fn typed_reductions_report_the_wrong_dtype() {
    for Typed {
        name,
        reduce,
        dtype,
        ..
    } in TYPED_REDUCTIONS
    {
        let wrong = if dtype == DataType::Float64 {
            DataType::Int32
        } else {
            DataType::Float64
        };
        let s = one_to_four("wrong", &wrong);
        clear_last_error();
        assert_eq!(reduce(s).0, -1, "{}", name);
        let reason = recorded_error().unwrap_or_else(|| panic!("{}", name));
        let expected = format!("invalid series dtype: expected `{:?}`", dtype);
        assert!(reason.contains(&expected), "{}: {}", name, reason);
        assert!(reason.contains("`wrong`"), "{}: {}", name, reason);
        series_drop(s);
    }
}

#[test]
fn typed_reductions_of_nulls_are_undefined_but_the_sum() {
    for Typed {
        name,
        reduce,
        dtype,
        of_nulls,
        ..
    } in TYPED_REDUCTIONS
    {
        let s = boxed(Series::full_null("nulls".into(), 3, &dtype));
        clear_last_error();
        assert_eq!(reduce(s), of_nulls, "{}", name);
        assert_eq!(recorded_error(), None, "{}", name);
        series_drop(s);
    }
}

#[test]
fn reductions_clear_a_stale_reason() {
    let reductions = TYPED_REDUCTIONS
        .iter()
        .map(|row| (row.name, row.reduce, row.dtype.clone()))
        .chain(
            OTHER_REDUCTIONS
                .iter()
                .map(|(name, reduce)| (*name, *reduce, DataType::Float64)),
        );
    for (name, reduce, dtype) in reductions {
        let s = one_to_four("xs", &dtype);
        set_last_error("stale");
        assert!(reduce(s).0 >= 0, "{}", name);
        assert_eq!(recorded_error(), None, "{}", name);
        series_drop(s);
    }
}

#[test]
fn reductions_of_a_null_series_report_it() {
    let reductions = TYPED_REDUCTIONS
        .iter()
        .map(|row| (row.name, row.reduce))
        .chain(OTHER_REDUCTIONS);
    for (name, reduce) in reductions {
        clear_last_error();
        assert_eq!(reduce(ptr::null()).0, -1, "{}", name);
        assert_eq!(
            recorded_error().as_deref(),
            Some("series is null"),
            "{}",
            name
        );
    }
}

#[test]
fn std_var_defaults_to_ddof_1() {
    let s = make_f64("ys", &[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]);
    let var1 = series_var_v2(s, 1);
    assert_eq!(var1.valid, 1);
    assert!((var1.value - (32.0 / 7.0)).abs() < 1e-9);
    let std1 = series_std_v2(s, 1);
    assert_eq!(std1.valid, 1);
    assert!((std1.value - (32.0 / 7.0_f64).sqrt()).abs() < 1e-9);
    let var0 = series_var_v2(s, 0);
    assert!((var0.value - 4.0).abs() < 1e-9);
    series_drop(s);
}

#[test]
fn std_var_of_strings_are_undefined_not_failures() {
    let s = make_str("s", &["a", "b"]);
    set_last_error("stale");
    assert_eq!(series_std_v2(s, 1).valid, 0);
    assert_eq!(recorded_error(), None);
    set_last_error("stale");
    assert_eq!(series_var_v2(s, 1).valid, 0);
    assert_eq!(recorded_error(), None);
    series_drop(s);
}

#[test]
fn n_unique_counts_distinct_entries() {
    let s = make_i32("xs", &[1, 2, 2, 3, 3, 3]);
    assert_eq!(series_n_unique_v2(s), 3);
    series_drop(s);
}

#[test]
fn quantile_reports_a_list_series() {
    let rows = [
        Series::new("".into(), &[1i64, 2]),
        Series::new("".into(), &[3i64]),
    ];
    let s = boxed(Series::new("lists".into(), &rows));
    clear_last_error();
    assert_eq!(series_quantile_v2(s, 0.5, 0).valid, -1);
    let reason = recorded_error().expect("a reason");
    assert!(reason.contains("cannot cast List type"), "{}", reason);
    series_drop(s);
}

#[test]
fn quantile_refuses_an_unknown_method_code() {
    let s = make_f64("ys", &[1.0, 2.0]);
    clear_last_error();
    assert_eq!(series_quantile_v2(s, 0.5, 9).valid, -1);
    assert_eq!(
        recorded_error().as_deref(),
        Some("unknown quantile method code 9")
    );
    series_drop(s);
}
