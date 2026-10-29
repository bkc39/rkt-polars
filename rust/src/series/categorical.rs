use crate::prelude::*;
use crate::*;

pub(crate) fn enum_dtype(categories: StrListArg) -> Option<DataType> {
    let names = record(unsafe { str_list_arg(categories) })?;
    record(FrozenCategories::new(names)).map(DataType::from_frozen_categories)
}

/// Marks a reason whose rest is the JSON payload that Racket renders as its
/// own message for an Enum cast that misses values.
pub(crate) const ENUM_MISSES_TAG: &str = "\u{1}enum-misses\u{1}";

const ENUM_MISSES_SHOWN: usize = 10;

fn json_string(out: &mut String, value: &str) {
    out.push('"');
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            c if (c as u32) < 0x20 => {
                out.push_str(&format!("\\u{:04x}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

fn json_strings<'a>(out: &mut String, values: impl Iterator<Item = &'a str>) {
    out.push('[');
    for (i, value) in values.enumerate() {
        if i > 0 {
            out.push(',');
        }
        json_string(out, value);
    }
    out.push(']');
}

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
    let mut distinct: Vec<&str> = missed.iter().flatten().collect();
    distinct.sort_unstable();
    distinct.dedup();
    let mut payload = String::from(ENUM_MISSES_TAG);
    payload.push_str("{\"categories\":");
    json_strings(&mut payload, categories.categories().values_iter());
    payload.push_str(&format!(
        ",\"missing\":{},\"total\":{},\"distinct\":{},\"shown\":",
        missed.len(),
        strings.len() - strings.null_count(),
        distinct.len()
    ));
    json_strings(
        &mut payload,
        distinct.iter().copied().take(ENUM_MISSES_SHOWN),
    );
    payload.push('}');
    Err(PolarsError::ComputeError(payload.into()))
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
