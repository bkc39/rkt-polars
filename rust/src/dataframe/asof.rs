use crate::prelude::*;
use crate::*;

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatAsofStrategy {
    Backward = 1,
    Forward = 2,
    Nearest = 3,
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatAsofToleranceKind {
    None = 0,
    Integer = 1,
    Float = 2,
}

pub(crate) fn compat_asof_strategy(
    code: i32,
) -> Option<polars::prelude::AsofStrategy> {
    match code {
        x if x == CompatAsofStrategy::Backward as i32 => {
            Some(polars::prelude::AsofStrategy::Backward)
        }
        x if x == CompatAsofStrategy::Forward as i32 => {
            Some(polars::prelude::AsofStrategy::Forward)
        }
        x if x == CompatAsofStrategy::Nearest as i32 => {
            Some(polars::prelude::AsofStrategy::Nearest)
        }
        _ => None,
    }
}

pub(crate) fn compat_asof_tolerance(
    dtype: &DataType,
    kind: i32,
    integer: i64,
    float: f64,
) -> Option<Option<AnyValue<'static>>> {
    use CompatAsofToleranceKind as Kind;
    if kind == Kind::None as i32 {
        return Some(None);
    }
    Some(Some(match (dtype.to_physical(), kind) {
        (DataType::Int32, x) if x == Kind::Integer as i32 => {
            AnyValue::Int32(integer.try_into().ok()?)
        }
        (DataType::Int64, x) if x == Kind::Integer as i32 => {
            AnyValue::Int64(integer)
        }
        (DataType::UInt32, x) if x == Kind::Integer as i32 => {
            AnyValue::UInt32(integer.try_into().ok()?)
        }
        (DataType::UInt64, x) if x == Kind::Integer as i32 => {
            AnyValue::UInt64(integer.try_into().ok()?)
        }
        (DataType::Float32, x) if x == Kind::Float as i32 => {
            AnyValue::Float32(float as f32)
        }
        (DataType::Float64, x) if x == Kind::Float as i32 => {
            AnyValue::Float64(float)
        }
        _ => return None,
    }))
}

#[allow(clippy::too_many_arguments)]
fn asof_frames(
    left: &DataFrame,
    right: &DataFrame,
    left_on: &str,
    right_on: &str,
    strategy: i32,
    left_by: &[String],
    right_by: &[String],
    tolerance: (i32, i64, f64),
) -> PolarsResult<DataFrame> {
    let Some(strategy) = compat_asof_strategy(strategy) else {
        polars_bail!(InvalidOperation: "unknown asof strategy {}", strategy);
    };
    polars_ensure!(
        left_by.len() == right_by.len(),
        InvalidOperation: "the left and right by-keys differ in number: {} and {}",
        left_by.len(),
        right_by.len()
    );
    let left_key = left.column(left_on)?.as_materialized_series();
    let right_key = right.column(right_on)?.as_materialized_series();
    let (kind, integer, float) = tolerance;
    let Some(tolerance) =
        compat_asof_tolerance(left_key.dtype(), kind, integer, float)
    else {
        polars_bail!(
            InvalidOperation: "a tolerance cannot apply to a key of dtype {}",
            left_key.dtype()
        );
    };
    if left_by.is_empty() {
        left._join_asof(
            right, left_key, right_key, strategy, tolerance, None, None, true,
            true, true,
        )
    } else {
        // Polars cannot check sortedness within `by` groups; `true` would
        // only print a warning to stderr.
        left.join_asof_by(
            right,
            left_on,
            right_on,
            left_by.iter(),
            right_by.iter(),
            strategy,
            tolerance,
            true,
            false,
        )
    }
}

#[no_mangle]
pub extern "C" fn dataframe_join_asof(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on: *const c_char,
    right_on: *const c_char,
    strategy: i32,
) -> *mut DataFrame {
    dataframe_join_asof_options(
        left_ptr,
        right_ptr,
        left_on,
        right_on,
        strategy,
        ptr::null(),
        0,
        ptr::null(),
        0,
        CompatAsofToleranceKind::None as i32,
        0,
        0.0,
    )
}

#[no_mangle]
pub extern "C" fn dataframe_join_asof_options(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on: *const c_char,
    right_on: *const c_char,
    strategy: i32,
    left_by_ptrs: *const *const c_char,
    n_left_by: usize,
    right_by_ptrs: *const *const c_char,
    n_right_by: usize,
    tolerance_kind: i32,
    tolerance_integer: i64,
    tolerance_float: f64,
) -> *mut DataFrame {
    clear_last_error();
    let (Some(left), Some(right)) =
        (unsafe { left_ptr.as_ref() }, unsafe { right_ptr.as_ref() })
    else {
        set_last_error("dataframe is null");
        return ptr::null_mut();
    };
    let (Some(left_on), Some(right_on)) = (
        decode_c_str(left_on, "the left key"),
        decode_c_str(right_on, "the right key"),
    ) else {
        return ptr::null_mut();
    };
    let keys = unsafe {
        (
            collect_c_strings(left_by_ptrs, n_left_by),
            collect_c_strings(right_by_ptrs, n_right_by),
        )
    };
    let (Some(left_by), Some(right_by)) = keys else {
        set_last_error("a by-key is null or not valid UTF-8");
        return ptr::null_mut();
    };
    let tolerance = (tolerance_kind, tolerance_integer, tolerance_float);
    guard_panic(|| {
        record(asof_frames(
            left, right, left_on, right_on, strategy, &left_by, &right_by,
            tolerance,
        ))
    })
    .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

fn decode_c_str<'a>(p: *const c_char, what: &str) -> Option<&'a str> {
    if p.is_null() {
        set_last_error(format!("{} is null", what));
        return None;
    }
    record(
        unsafe { CStr::from_ptr(p) }
            .to_str()
            .map_err(|err| format!("{} is not valid UTF-8: {}", what, err)),
    )
}
