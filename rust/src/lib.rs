mod prelude {
    pub(crate) use chrono::{
        DateTime, Datelike, Duration as ChronoDuration, NaiveDate,
        NaiveDateTime, Timelike,
    };
    pub(crate) use polars::prelude::*;
    pub(crate) use std::ffi::{CStr, CString};
    pub(crate) use std::os::raw::c_char;
    pub(crate) use std::ptr;
}

#[cfg(test)]
pub(crate) use prelude::*;

mod dataframe;
mod expr;
mod ffi;
mod lazyframe;
mod series;
mod types;

pub use dataframe::*;
pub use expr::*;
pub use ffi::*;
pub use lazyframe::*;
pub use series::*;
pub use types::*;

pub(crate) use ffi::{
    boxed_result, boxed_unguarded, clear_last_error, collect_c_strings,
    collect_exprs, decode_path, decode_schema, deref_arg, deref_mut_arg,
    guard_panic, name_arg, named_sort, record, scalar_result, set_last_error,
    slice_or_empty, sort_multiple_options, str_list_arg, str_list_out, str_out,
};
#[cfg(test)]
pub(crate) use ffi::{on_polars_worker, panic_is_quiet};
#[cfg(test)]
pub(crate) use ffi::{str_arg, StrError};
#[cfg(test)]
pub(crate) use series::ymdhms_to_naive_datetime;
pub(crate) use series::{
    ambiguous_name, datetime_tz_dtype, enum_dtype, name_from_ptr,
    named_time_zone, optional_time_zone, series_new, tz_resolution,
    valid_slices,
};
#[cfg(test)]
pub(crate) use types::compat_time_unit_from_polars;
pub(crate) use types::{compat_dtype_from_polars, polars_dtype_from_compat};

#[cfg(test)]
mod tests;
