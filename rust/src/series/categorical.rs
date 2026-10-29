use crate::prelude::*;
use crate::*;
use std::collections::BTreeSet;

pub(crate) fn enum_dtype(categories: StrListArg) -> Option<DataType> {
    let names = record(unsafe { str_list_arg(categories) })?;
    record(FrozenCategories::new(names)).map(DataType::from_frozen_categories)
}

/// Marks a reason whose rest is the JSON payload that Racket renders as its
/// own message for an Enum cast that misses values.
pub(crate) const ENUM_MISSES_TAG: &str = "\u{1}enum-misses\u{1}";

const ENUM_MISSES_SHOWN: usize = 10;

/// The cast of a String, Categorical or Enum series to the Enum `dtype`,
/// failing with the tagged payload when a value is not a category. Any
/// other source is cast strictly.
pub(crate) fn enum_cast_checked(
    s: &Series,
    dtype: &DataType,
) -> PolarsResult<Series> {
    let DataType::Enum(categories, _) = dtype else {
        return s.strict_cast(dtype);
    };
    let strings = match s.dtype() {
        DataType::String => s.clone(),
        DataType::Categorical(..) | DataType::Enum(..) => {
            s.cast(&DataType::String)?
        }
        _ => return s.strict_cast(dtype),
    };
    let out = strings.cast(dtype)?;
    if out.null_count() == strings.null_count() {
        return Ok(out);
    }
    let missed_mask = out.is_null() & strings.is_not_null();
    let missed = strings.str()?.filter(&missed_mask)?;
    let mut distinct = PlHashSet::new();
    let mut shown = BTreeSet::new();
    for value in missed.iter().flatten() {
        if distinct.insert(value) {
            shown.insert(value);
            if shown.len() > ENUM_MISSES_SHOWN {
                shown.pop_last();
            }
        }
    }
    let payload = serde_json::json!({
        "categories": categories.categories().values_iter().collect::<Vec<_>>(),
        "missing": missed.len(),
        "total": strings.len() - strings.null_count(),
        "distinct": distinct.len(),
        "shown": shown,
    });
    Err(PolarsError::ComputeError(
        format!("{ENUM_MISSES_TAG}{payload}").into(),
    ))
}

#[no_mangle]
pub extern "C" fn series_cast_enum_v2(
    s_ptr: *const Series,
    categories: StrListArg,
) -> *mut Series {
    clear_last_error();
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        set_last_error("series is null");
        return ptr::null_mut();
    };
    enum_dtype(categories)
        .and_then(|dtype| guard_panic(|| record(enum_cast_checked(s, &dtype))))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

#[no_mangle]
pub extern "C" fn series_enum_categories(s_ptr: *const Series) -> *mut Series {
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return ptr::null_mut();
    };
    match s.dtype() {
        DataType::Enum(categories, _) => {
            let names = StringChunked::with_chunk(
                s.name().clone(),
                categories.categories().clone(),
            );
            Box::into_raw(Box::new(names.into_series()))
        }
        _ => ptr::null_mut(),
    }
}
