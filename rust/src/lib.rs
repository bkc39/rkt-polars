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

pub(crate) use ffi::{collect_c_strings, collect_exprs, rust_string_to_ptr};
#[cfg(test)]
pub(crate) use series::ymdhms_to_naive_datetime;
pub(crate) use series::{name_from_ptr, series_new, valid_slices};
#[cfg(test)]
pub(crate) use types::compat_time_unit_from_polars;
pub(crate) use types::{compat_dtype_from_polars, polars_dtype_from_compat};

#[cfg(test)]
mod tests;
