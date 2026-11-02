use super::test_util;
use super::*;

mod categorical;
mod constructor_smoke;
mod copy;
mod ctors;
mod dtype_tag;
mod opt_ctors;
mod packed_str;
mod smoke;
mod value_access;

/// Collect the bool entries of a boolean Series (such as a comparison
/// or `is_null` result) into a `Vec<bool>` for compact assertions.
fn read_bool_series(s: *mut Series) -> Vec<bool> {
    let n = series_len(s);
    (0..n)
        .map(|i| {
            let v = series_ref_bool(s, i);
            assert_eq!(v.valid, 1, "unexpected null at index {}", i);
            v.value != 0
        })
        .collect()
}

type ScalarOp = fn(*mut Series) -> *mut Series;

type ScalarRow = (&'static str, ScalarOp, &'static str);

macro_rules! scalar_ops {
    ($($dtype:literal $v:literal: [$($f:ident),+ $(,)?]),+ $(,)?) => {
        &[$($((stringify!($f), (|s| $f(s, $v)) as ScalarOp, $dtype),)+)+]
    };
}

fn make_of(dtype: &str, name: &str) -> *mut Series {
    let n = test_util::cstr(name);
    let s = match dtype {
        "Int32" => series_new_i32(n.as_ptr(), [3i32, 4].as_ptr(), 2),
        "Int64" => series_new_i64(n.as_ptr(), [3i64, 4].as_ptr(), 2),
        "UInt32" => series_new_u32(n.as_ptr(), [3u32, 4].as_ptr(), 2),
        "UInt64" => series_new_u64(n.as_ptr(), [3u64, 4].as_ptr(), 2),
        "Float64" => series_new_f64(n.as_ptr(), [3.0, 4.0].as_ptr(), 2),
        _ => unreachable!("{}", dtype),
    };
    assert!(!s.is_null());
    s
}

fn wrong_dtype_for(dtype: &str) -> &'static str {
    if dtype == "Float64" {
        "Int32"
    } else {
        "Float64"
    }
}

fn assert_ops_clear_a_stale_reason(ops: &[ScalarRow]) {
    for &(name, op, dtype) in ops {
        let s = make_of(dtype, "xs");
        set_last_error("stale");
        let out = op(s);
        assert!(!out.is_null(), "{}", name);
        assert_eq!(test_util::recorded_error(), None, "{}", name);
        series_drop(out);
        series_drop(s);
    }
}

fn assert_ops_report_the_wrong_dtype(ops: &[ScalarRow]) {
    for &(name, op, dtype) in ops {
        let s = make_of(wrong_dtype_for(dtype), "wrong");
        clear_last_error();
        assert!(op(s).is_null(), "{}", name);
        let reason =
            test_util::recorded_error().unwrap_or_else(|| panic!("{}", name));
        let expected = format!("invalid series dtype: expected `{}`", dtype);
        assert!(reason.contains(&expected), "{}: {}", name, reason);
        assert!(reason.contains("`wrong`"), "{}: {}", name, reason);
        series_drop(s);
    }
}

fn assert_ops_report_a_null_series(ops: &[ScalarRow]) {
    for &(name, op, _) in ops {
        clear_last_error();
        assert!(op(ptr::null_mut()).is_null(), "{}", name);
        assert_eq!(
            test_util::recorded_error().as_deref(),
            Some("series is null"),
            "{}",
            name
        );
    }
}

mod arith_scalar;
mod arith_series;
mod boolean;
mod cast;
mod cmp_scalar;
mod cmp_series;
mod reductions;
mod reshaping;
