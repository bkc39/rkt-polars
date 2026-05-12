use chrono::{
    DateTime, Datelike, Duration as ChronoDuration, NaiveDate, NaiveDateTime,
    Timelike,
};
use polars::prelude::*;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

/// A struct to represent a tuple (usize, usize) for C FFI
#[repr(C)]
pub struct Shape {
    pub rows: usize,
    pub cols: usize,
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatDTypeTag {
    Unknown = 0,
    Boolean = 1,
    UInt8 = 2,
    UInt16 = 3,
    UInt32 = 4,
    UInt64 = 5,
    Int8 = 6,
    Int16 = 7,
    Int32 = 8,
    Int64 = 9,
    Float32 = 10,
    Float64 = 11,
    String = 12,
    Binary = 13,
    BinaryOffset = 14,
    Date = 15,
    Datetime = 16,
    Duration = 17,
    Time = 18,
    Null = 19,
    List = 20,
    Array = 21,
    Struct = 22,
    Categorical = 23,
    Enum = 24,
    Decimal = 25,
    Object = 26,
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatTimeUnit {
    None = 0,
    Nanoseconds = 1,
    Microseconds = 2,
    Milliseconds = 3,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatDType {
    pub tag: i32,
    pub time_unit: i32,
    pub flags: u32,
    pub array_width: usize,
}

const COMPAT_DTYPE_HAS_TIMEZONE: u32 = 0x1;

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI32 {
    pub valid: i32,
    pub value: i32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI8 {
    pub valid: i32,
    pub value: i8,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI16 {
    pub valid: i32,
    pub value: i16,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct CompatOptF64 {
    pub valid: i32,
    pub value: f64,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct CompatOptF32 {
    pub valid: i32,
    pub value: f32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptI64 {
    pub valid: i32,
    pub value: i64,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU8 {
    pub valid: i32,
    pub value: u8,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU16 {
    pub valid: i32,
    pub value: u16,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU32 {
    pub valid: i32,
    pub value: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptU64 {
    pub valid: i32,
    pub value: u64,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptBool {
    pub valid: i32,
    pub value: i32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct YMD {
    pub year: i32,
    pub month: u32,
    pub day: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptYMD {
    pub valid: i32,
    pub value: YMD,
}

impl CompatOptI32 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: i32) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<i32>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptI8 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: i8) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<i8>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptI16 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: i16) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<i16>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptF64 {
    const NONE: Self = Self {
        valid: 0,
        value: 0.0,
    };
    fn some(v: f64) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<f64>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptF32 {
    const NONE: Self = Self {
        valid: 0,
        value: 0.0,
    };
    fn some(v: f32) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<f32>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptI64 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: i64) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<i64>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU8 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: u8) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<u8>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU16 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: u16) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<u16>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU32 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: u32) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<u32>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptU64 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: u64) -> Self {
        Self { valid: 1, value: v }
    }
    fn from_option(o: Option<u64>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptBool {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: bool) -> Self {
        Self {
            valid: 1,
            value: if v { 1 } else { 0 },
        }
    }
    fn from_option(o: Option<bool>) -> Self {
        match o {
            Some(v) => Self::some(v),
            None => Self::NONE,
        }
    }
}

impl CompatOptYMD {
    const NONE: Self = Self {
        valid: 0,
        value: YMD {
            year: 0,
            month: 0,
            day: 0,
        },
    };

    fn some(v: YMD) -> Self {
        Self { valid: 1, value: v }
    }
}

#[no_mangle]
pub extern "C" fn string_drop(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

fn rust_string_to_ptr(value: impl AsRef<str>) -> *const c_char {
    CString::new(value.as_ref())
        .map(CString::into_raw)
        .map(|ptr| ptr as *const c_char)
        .unwrap_or(ptr::null())
}

fn compat_time_unit_from_polars(time_unit: &TimeUnit) -> CompatTimeUnit {
    match time_unit {
        TimeUnit::Nanoseconds => CompatTimeUnit::Nanoseconds,
        TimeUnit::Microseconds => CompatTimeUnit::Microseconds,
        TimeUnit::Milliseconds => CompatTimeUnit::Milliseconds,
    }
}

/// Inverse of `compat_dtype_from_polars`: lift a CompatDType (as it
/// appears across the FFI) back to a polars DataType.  Datetime and
/// Duration default to Microseconds when the time-unit field is None;
/// timezone is always None for now (no Racket-side surface yet).
/// Returns None for unknown tags or for nested/parameterized dtypes
/// that we don't yet expose for input.
fn polars_dtype_from_compat(c: &CompatDType) -> Option<DataType> {
    use CompatDTypeTag as Tag;
    let tu = match c.time_unit {
        x if x == CompatTimeUnit::Nanoseconds as i32 => TimeUnit::Nanoseconds,
        x if x == CompatTimeUnit::Microseconds as i32 => TimeUnit::Microseconds,
        x if x == CompatTimeUnit::Milliseconds as i32 => TimeUnit::Milliseconds,
        _ => TimeUnit::Microseconds,
    };
    Some(match c.tag {
        x if x == Tag::Boolean as i32 => DataType::Boolean,
        x if x == Tag::UInt8 as i32 => DataType::UInt8,
        x if x == Tag::UInt16 as i32 => DataType::UInt16,
        x if x == Tag::UInt32 as i32 => DataType::UInt32,
        x if x == Tag::UInt64 as i32 => DataType::UInt64,
        x if x == Tag::Int8 as i32 => DataType::Int8,
        x if x == Tag::Int16 as i32 => DataType::Int16,
        x if x == Tag::Int32 as i32 => DataType::Int32,
        x if x == Tag::Int64 as i32 => DataType::Int64,
        x if x == Tag::Float32 as i32 => DataType::Float32,
        x if x == Tag::Float64 as i32 => DataType::Float64,
        x if x == Tag::String as i32 => DataType::String,
        x if x == Tag::Binary as i32 => DataType::Binary,
        x if x == Tag::Date as i32 => DataType::Date,
        x if x == Tag::Datetime as i32 => DataType::Datetime(tu, None),
        x if x == Tag::Duration as i32 => DataType::Duration(tu),
        x if x == Tag::Time as i32 => DataType::Time,
        x if x == Tag::Null as i32 => DataType::Null,
        _ => return None,
    })
}

#[allow(unexpected_cfgs)]
fn compat_dtype_from_polars(dtype: &DataType) -> CompatDType {
    use CompatDTypeTag as Tag;

    // TODO: Preserve nested/parameterized dtype payloads for List/Array/Struct
    // instead of exposing only the top-level constructor and array width.
    match dtype {
        DataType::Boolean => CompatDType {
            tag: Tag::Boolean as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::UInt8 => CompatDType {
            tag: Tag::UInt8 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::UInt16 => CompatDType {
            tag: Tag::UInt16 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::UInt32 => CompatDType {
            tag: Tag::UInt32 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::UInt64 => CompatDType {
            tag: Tag::UInt64 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Int8 => CompatDType {
            tag: Tag::Int8 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Int16 => CompatDType {
            tag: Tag::Int16 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Int32 => CompatDType {
            tag: Tag::Int32 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Int64 => CompatDType {
            tag: Tag::Int64 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Float32 => CompatDType {
            tag: Tag::Float32 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Float64 => CompatDType {
            tag: Tag::Float64 as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::String => CompatDType {
            tag: Tag::String as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Binary => CompatDType {
            tag: Tag::Binary as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::BinaryOffset => CompatDType {
            tag: Tag::BinaryOffset as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Date => CompatDType {
            tag: Tag::Date as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Datetime(time_unit, timezone) => CompatDType {
            tag: Tag::Datetime as i32,
            time_unit: compat_time_unit_from_polars(time_unit) as i32,
            flags: if timezone.is_some() {
                COMPAT_DTYPE_HAS_TIMEZONE
            } else {
                0
            },
            array_width: 0,
        },
        DataType::Duration(time_unit) => CompatDType {
            tag: Tag::Duration as i32,
            time_unit: compat_time_unit_from_polars(time_unit) as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Time => CompatDType {
            tag: Tag::Time as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::List(_) => CompatDType {
            tag: Tag::List as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        #[cfg(feature = "dtype-array")]
        DataType::Array(_, width) => CompatDType {
            tag: Tag::Array as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: *width,
        },
        DataType::Null => CompatDType {
            tag: Tag::Null as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        DataType::Struct(_) => CompatDType {
            tag: Tag::Struct as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        // Categorical/Enum/Decimal/Object exist as variants in polars but only
        // when their respective features are enabled in the polars build.
        // We don't enable any of those today; route anything we don't recognize
        // through Unknown so the match stays exhaustive.
        DataType::Unknown(_) => CompatDType {
            tag: Tag::Unknown as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
    }
}

#[no_mangle]
pub extern "C" fn dataframe_make() -> *mut DataFrame {
    let df = DataFrame::default();
    let boxed_df = Box::new(df);
    Box::into_raw(boxed_df)
}

#[no_mangle]
pub extern "C" fn dataframe_empty() -> *mut DataFrame {
    Box::into_raw(Box::new(DataFrame::empty()))
}

#[no_mangle]
pub extern "C" fn dataframe_drop(df_ptr: *mut DataFrame) {
    if !df_ptr.is_null() {
        unsafe { drop(Box::from_raw(df_ptr)) };
    }
}

#[no_mangle]
pub extern "C" fn dataframe_new(
    series_ptrs: *const *const Series,
    length: usize,
) -> *mut DataFrame {
    if series_ptrs.is_null() && length != 0 {
        return ptr::null_mut();
    }
    let columns: Vec<Series> = if length == 0 {
        Vec::new()
    } else {
        let slice = unsafe { std::slice::from_raw_parts(series_ptrs, length) };
        if slice.iter().any(|p| p.is_null()) {
            return ptr::null_mut();
        }
        slice.iter().map(|&p| unsafe { (&*p).clone() }).collect()
    };
    match DataFrame::new(columns) {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_height(df_ptr: *mut DataFrame) -> usize {
    if df_ptr.is_null() {
        0
    } else {
        unsafe { (&*df_ptr).height() }
    }
}

#[no_mangle]
pub extern "C" fn dataframe_width(df_ptr: *mut DataFrame) -> usize {
    if df_ptr.is_null() {
        0
    } else {
        unsafe { (&*df_ptr).width() }
    }
}

#[no_mangle]
pub extern "C" fn dataframe_head(
    df_ptr: *mut DataFrame,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    Box::into_raw(Box::new(df.head(Some(n))))
}

#[no_mangle]
pub extern "C" fn dataframe_tail(
    df_ptr: *mut DataFrame,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    Box::into_raw(Box::new(df.tail(Some(n))))
}

#[no_mangle]
pub extern "C" fn dataframe_slice(
    df_ptr: *mut DataFrame,
    offset: i64,
    length: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    Box::into_raw(Box::new(df.slice(offset, length)))
}

#[no_mangle]
pub extern "C" fn dataframe_select(
    df_ptr: *mut DataFrame,
    name_ptrs: *const *const c_char,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(name_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    match df.select(&names) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_drop_columns(
    df_ptr: *mut DataFrame,
    name_ptrs: *const *const c_char,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(name_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    let mut out = df.clone();
    for name in &names {
        match out.drop_in_place(name) {
            Ok(_) => {}
            Err(_) => return ptr::null_mut(),
        }
    }
    Box::into_raw(Box::new(out))
}

#[no_mangle]
pub extern "C" fn dataframe_rename(
    df_ptr: *mut DataFrame,
    old: *const c_char,
    new: *const c_char,
) -> *mut DataFrame {
    if df_ptr.is_null() || old.is_null() || new.is_null() {
        return ptr::null_mut();
    }
    let old_str = match unsafe { CStr::from_ptr(old).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let new_str = match unsafe { CStr::from_ptr(new).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    let mut out = df.clone();
    match out.rename(old_str, new_str) {
        Ok(_) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_with_column(
    df_ptr: *mut DataFrame,
    series_ptr: *const Series,
) -> *mut DataFrame {
    if df_ptr.is_null() || series_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let s = unsafe { &*series_ptr };
    let mut out = df.clone();
    match out.with_column(s.clone()) {
        Ok(_) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_column_name(
    df_ptr: *mut DataFrame,
    index: usize,
) -> *const c_char {
    if df_ptr.is_null() {
        return ptr::null();
    }
    let df = unsafe { &*df_ptr };
    let names = df.get_column_names();
    match names.get(index) {
        Some(name) => rust_string_to_ptr(*name),
        None => ptr::null(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_column(
    df_ptr: *mut DataFrame,
    name: *const c_char,
) -> *mut Series {
    if df_ptr.is_null() || name.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let name_str = match unsafe { CStr::from_ptr(name).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match df.column(name_str) {
        Ok(s) => Box::into_raw(Box::new(s.clone())),
        Err(_) => ptr::null_mut(),
    }
}

macro_rules! cmp_scalar {
    ($name:ident, $op:ident, $downcast:ident, $rhs_ty:ty) => {
        #[no_mangle]
        pub extern "C" fn $name(
            s_ptr: *mut Series,
            rhs: $rhs_ty,
        ) -> *mut Series {
            if s_ptr.is_null() {
                return ptr::null_mut();
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => Box::into_raw(Box::new(ca.$op(rhs).into_series())),
                Err(_) => ptr::null_mut(),
            }
        }
    };
}

cmp_scalar!(series_lt_i32, lt, i32, i32);
cmp_scalar!(series_le_i32, lt_eq, i32, i32);
cmp_scalar!(series_gt_i32, gt, i32, i32);
cmp_scalar!(series_ge_i32, gt_eq, i32, i32);
cmp_scalar!(series_eq_i32, equal, i32, i32);
cmp_scalar!(series_ne_i32, not_equal, i32, i32);

cmp_scalar!(series_lt_f64, lt, f64, f64);
cmp_scalar!(series_le_f64, lt_eq, f64, f64);
cmp_scalar!(series_gt_f64, gt, f64, f64);
cmp_scalar!(series_ge_f64, gt_eq, f64, f64);
cmp_scalar!(series_eq_f64, equal, f64, f64);
cmp_scalar!(series_ne_f64, not_equal, f64, f64);

#[no_mangle]
pub extern "C" fn series_eq_str(
    s_ptr: *mut Series,
    rhs: *const c_char,
) -> *mut Series {
    if s_ptr.is_null() || rhs.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    let rhs_str = match unsafe { CStr::from_ptr(rhs).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match s.str() {
        Ok(ca) => Box::into_raw(Box::new(ca.equal(rhs_str).into_series())),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_ne_str(
    s_ptr: *mut Series,
    rhs: *const c_char,
) -> *mut Series {
    if s_ptr.is_null() || rhs.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    let rhs_str = match unsafe { CStr::from_ptr(rhs).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match s.str() {
        Ok(ca) => Box::into_raw(Box::new(ca.not_equal(rhs_str).into_series())),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_is_null(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.is_null().into_series()))
}

#[no_mangle]
pub extern "C" fn series_is_not_null(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.is_not_null().into_series()))
}

macro_rules! bool_binop {
    ($name:ident, $op:tt) => {
        #[no_mangle]
        pub extern "C" fn $name(a_ptr: *mut Series, b_ptr: *mut Series) -> *mut Series {
            if a_ptr.is_null() || b_ptr.is_null() {
                return ptr::null_mut();
            }
            let a = unsafe { &*a_ptr };
            let b = unsafe { &*b_ptr };
            let (a_ca, b_ca) = match (a.bool(), b.bool()) {
                (Ok(x), Ok(y)) => (x, y),
                _ => return ptr::null_mut(),
            };
            let result = a_ca $op b_ca;
            Box::into_raw(Box::new(result.into_series()))
        }
    };
}

bool_binop!(series_and, &);
bool_binop!(series_or, |);
bool_binop!(series_xor, ^);

#[no_mangle]
pub extern "C" fn series_not(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    match s.bool() {
        Ok(ca) => Box::into_raw(Box::new((!ca).into_series())),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_filter(
    df_ptr: *mut DataFrame,
    mask_ptr: *mut Series,
) -> *mut DataFrame {
    if df_ptr.is_null() || mask_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let mask = unsafe { &*mask_ptr };
    let bool_ca = match mask.bool() {
        Ok(ca) => ca,
        Err(_) => return ptr::null_mut(),
    };
    match df.filter(bool_ca) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

unsafe fn collect_c_strings(
    ptrs: *const *const c_char,
    n: usize,
) -> Option<Vec<String>> {
    if n == 0 {
        return Some(Vec::new());
    }
    if ptrs.is_null() {
        return None;
    }
    let slice = std::slice::from_raw_parts(ptrs, n);
    let mut out = Vec::with_capacity(n);
    for &p in slice {
        if p.is_null() {
            return None;
        }
        match CStr::from_ptr(p).to_str() {
            Ok(s) => out.push(s.to_string()),
            Err(_) => return None,
        }
    }
    Some(out)
}

#[no_mangle]
pub extern "C" fn dataframe_sort(
    df_ptr: *mut DataFrame,
    by_ptrs: *const *const c_char,
    descending_ptr: *const u8,
    n: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(by_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let descending: Vec<bool> = if n == 0 {
        Vec::new()
    } else if descending_ptr.is_null() {
        vec![false; n]
    } else {
        unsafe { std::slice::from_raw_parts(descending_ptr, n) }
            .iter()
            .map(|&b| b != 0)
            .collect()
    };
    let opts =
        SortMultipleOptions::new().with_order_descending_multi(descending);
    let df = unsafe { &*df_ptr };
    match df.sort(names, opts) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

macro_rules! group_by_agg {
    ($name:ident, $method:ident) => {
        #[no_mangle]
        pub extern "C" fn $name(
            df_ptr: *mut DataFrame,
            by_ptrs: *const *const c_char,
            n_by: usize,
            agg_ptrs: *const *const c_char,
            n_agg: usize,
        ) -> *mut DataFrame {
            if df_ptr.is_null() {
                return ptr::null_mut();
            }
            let by = match unsafe { collect_c_strings(by_ptrs, n_by) } {
                Some(v) => v,
                None => return ptr::null_mut(),
            };
            let agg = match unsafe { collect_c_strings(agg_ptrs, n_agg) } {
                Some(v) => v,
                None => return ptr::null_mut(),
            };
            let df = unsafe { &*df_ptr };
            let gb = match df.group_by(&by) {
                Ok(gb) => gb,
                Err(_) => return ptr::null_mut(),
            };
            #[allow(deprecated)]
            let result = gb.select(&agg).$method();
            match result {
                Ok(out) => Box::into_raw(Box::new(out)),
                Err(_) => ptr::null_mut(),
            }
        }
    };
}

group_by_agg!(dataframe_group_by_sum, sum);
group_by_agg!(dataframe_group_by_mean, mean);
group_by_agg!(dataframe_group_by_min, min);
group_by_agg!(dataframe_group_by_max, max);
group_by_agg!(dataframe_group_by_count, count);

#[no_mangle]
pub extern "C" fn dataframe_unique(df_ptr: *mut DataFrame) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    match df.unique(None, polars::prelude::UniqueKeepStrategy::Any, None) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_drop_nulls(
    df_ptr: *mut DataFrame,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let none: Option<&[String]> = None;
    match df.drop_nulls(none) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatJoinKind {
    Inner = 1,
    Left = 2,
    Outer = 3,
    Cross = 4,
    Semi = 5,
    Anti = 6,
}

#[no_mangle]
pub extern "C" fn dataframe_join(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on_ptrs: *const *const c_char,
    n_left_on: usize,
    right_on_ptrs: *const *const c_char,
    n_right_on: usize,
    how: i32,
) -> *mut DataFrame {
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    if how == CompatJoinKind::Cross as i32 {
        use polars::prelude::CrossJoin;
        return match left.cross_join(right, None, None) {
            Ok(out) => Box::into_raw(Box::new(out)),
            Err(_) => ptr::null_mut(),
        };
    }
    let join_type = match how {
        x if x == CompatJoinKind::Inner as i32 => {
            polars::prelude::JoinType::Inner
        }
        x if x == CompatJoinKind::Left as i32 => {
            polars::prelude::JoinType::Left
        }
        x if x == CompatJoinKind::Outer as i32 => {
            polars::prelude::JoinType::Full
        }
        x if x == CompatJoinKind::Semi as i32 => {
            polars::prelude::JoinType::Semi
        }
        x if x == CompatJoinKind::Anti as i32 => {
            polars::prelude::JoinType::Anti
        }
        _ => return ptr::null_mut(),
    };
    let left_on = match unsafe { collect_c_strings(left_on_ptrs, n_left_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let right_on = match unsafe { collect_c_strings(right_on_ptrs, n_right_on) }
    {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if left_on.is_empty() || right_on.is_empty() {
        return ptr::null_mut();
    }
    let args = polars::prelude::JoinArgs::new(join_type);
    match left.join(right, &left_on, &right_on, args) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

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

fn compat_asof_strategy(code: i32) -> Option<polars::prelude::AsofStrategy> {
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

fn compat_asof_tolerance(
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

#[no_mangle]
pub extern "C" fn dataframe_join_asof(
    left_ptr: *mut DataFrame,
    right_ptr: *mut DataFrame,
    left_on: *const c_char,
    right_on: *const c_char,
    strategy: i32,
) -> *mut DataFrame {
    if left_ptr.is_null()
        || right_ptr.is_null()
        || left_on.is_null()
        || right_on.is_null()
    {
        return ptr::null_mut();
    }
    let left_on_str = match unsafe { CStr::from_ptr(left_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_on_str = match unsafe { CStr::from_ptr(right_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let strategy = match compat_asof_strategy(strategy) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    let left_key = match left.column(left_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_key = match right.column(right_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match left._join_asof(
        right, left_key, right_key, strategy, None, None, None, true,
    ) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
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
    if left_ptr.is_null()
        || right_ptr.is_null()
        || left_on.is_null()
        || right_on.is_null()
    {
        return ptr::null_mut();
    }
    let left_on_str = match unsafe { CStr::from_ptr(left_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_on_str = match unsafe { CStr::from_ptr(right_on).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let strategy = match compat_asof_strategy(strategy) {
        Some(s) => s,
        None => return ptr::null_mut(),
    };
    let left_by = match unsafe { collect_c_strings(left_by_ptrs, n_left_by) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let right_by = match unsafe { collect_c_strings(right_by_ptrs, n_right_by) }
    {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if left_by.len() != right_by.len() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    let left_key = match left.column(left_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let right_key = match right.column(right_on_str) {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let tolerance = match compat_asof_tolerance(
        left_key.dtype(),
        tolerance_kind,
        tolerance_integer,
        tolerance_float,
    ) {
        Some(t) => t,
        None => return ptr::null_mut(),
    };
    let result = if left_by.is_empty() && right_by.is_empty() {
        left._join_asof(
            right, left_key, right_key, strategy, tolerance, None, None, true,
        )
    } else {
        left.join_asof_by(
            right,
            left_on_str,
            right_on_str,
            left_by.iter(),
            right_by.iter(),
            strategy,
            tolerance,
        )
    };
    match result {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_hstack(
    df_ptr: *mut DataFrame,
    series_ptrs: *const *const Series,
    length: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() || (series_ptrs.is_null() && length != 0) {
        return ptr::null_mut();
    }
    let columns: Vec<Series> = if length == 0 {
        Vec::new()
    } else {
        let slice = unsafe { std::slice::from_raw_parts(series_ptrs, length) };
        if slice.iter().any(|p| p.is_null()) {
            return ptr::null_mut();
        }
        slice.iter().map(|&p| unsafe { (&*p).clone() }).collect()
    };
    let df = unsafe { &*df_ptr };
    match df.hstack(&columns) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_vstack(
    a_ptr: *mut DataFrame,
    b_ptr: *mut DataFrame,
) -> *mut DataFrame {
    if a_ptr.is_null() || b_ptr.is_null() {
        return ptr::null_mut();
    }
    let a = unsafe { &*a_ptr };
    let b = unsafe { &*b_ptr };
    match a.vstack(b) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatPivotAgg {
    None = 0,
    First = 1,
    Sum = 2,
    Min = 3,
    Max = 4,
    Mean = 5,
    Count = 6,
}

fn compat_pivot_agg(code: i32) -> Option<Option<Expr>> {
    match code {
        x if x == CompatPivotAgg::None as i32 => Some(None),
        x if x == CompatPivotAgg::First as i32 => Some(Some(first())),
        x if x == CompatPivotAgg::Sum as i32 => Some(Some(col("").sum())),
        x if x == CompatPivotAgg::Min as i32 => Some(Some(col("").min())),
        x if x == CompatPivotAgg::Max as i32 => Some(Some(col("").max())),
        x if x == CompatPivotAgg::Mean as i32 => Some(Some(col("").mean())),
        x if x == CompatPivotAgg::Count as i32 => Some(Some(col("").count())),
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_pivot(
    df_ptr: *mut DataFrame,
    on_ptrs: *const *const c_char,
    n_on: usize,
    index_ptrs: *const *const c_char,
    n_index: usize,
    values_ptrs: *const *const c_char,
    n_values: usize,
    agg: i32,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let on = match unsafe { collect_c_strings(on_ptrs, n_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if on.is_empty() {
        return ptr::null_mut();
    }
    let index = match unsafe { collect_c_strings(index_ptrs, n_index) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let values = match unsafe { collect_c_strings(values_ptrs, n_values) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let agg_expr = match compat_pivot_agg(agg) {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    match polars::lazy::frame::pivot::pivot_stable(
        df,
        on,
        Some(index),
        Some(values),
        true,
        agg_expr,
        None,
    ) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_unpivot(
    df_ptr: *mut DataFrame,
    on_ptrs: *const *const c_char,
    n_on: usize,
    index_ptrs: *const *const c_char,
    n_index: usize,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let on = match unsafe { collect_c_strings(on_ptrs, n_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let index = match unsafe { collect_c_strings(index_ptrs, n_index) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let df = unsafe { &*df_ptr };
    match df.unpivot(on, index) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_write_csv(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    if df_ptr.is_null() || path.is_null() {
        return 1;
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return 2,
    };
    let mut file = match std::fs::File::create(path_str) {
        Ok(f) => f,
        Err(_) => return 3,
    };
    let df = unsafe { &mut *df_ptr };
    use polars::prelude::SerWriter;
    match polars::prelude::CsvWriter::new(&mut file)
        .include_header(true)
        .with_separator(b',')
        .finish(df)
    {
        Ok(_) => 0,
        Err(_) => 4,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_read_csv(path: *const c_char) -> *mut DataFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let file = match std::fs::File::open(path_str) {
        Ok(f) => f,
        Err(_) => return ptr::null_mut(),
    };
    use polars::prelude::SerReader;
    match polars::prelude::CsvReadOptions::default()
        .with_has_header(true)
        .into_reader_with_file_handle(file)
        .finish()
    {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_write_parquet(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    if df_ptr.is_null() || path.is_null() {
        return 1;
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return 2,
    };
    let mut file = match std::fs::File::create(path_str) {
        Ok(f) => f,
        Err(_) => return 3,
    };
    let df = unsafe { &mut *df_ptr };
    match polars::prelude::ParquetWriter::new(&mut file).finish(df) {
        Ok(_) => 0,
        Err(_) => 4,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_read_parquet(
    path: *const c_char,
) -> *mut DataFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let file = match std::fs::File::open(path_str) {
        Ok(f) => f,
        Err(_) => return ptr::null_mut(),
    };
    match polars::prelude::ParquetReader::new(file).finish() {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_write_json_lines(
    df_ptr: *mut DataFrame,
    path: *const c_char,
) -> i32 {
    if df_ptr.is_null() || path.is_null() {
        return 1;
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return 2,
    };
    let mut file = match std::fs::File::create(path_str) {
        Ok(f) => f,
        Err(_) => return 3,
    };
    let df = unsafe { &mut *df_ptr };
    use polars::prelude::SerWriter;
    match polars::prelude::JsonWriter::new(&mut file)
        .with_json_format(polars::prelude::JsonFormat::JsonLines)
        .finish(df)
    {
        Ok(_) => 0,
        Err(_) => 4,
    }
}

#[no_mangle]
pub extern "C" fn dataframe_read_json_lines(
    path: *const c_char,
) -> *mut DataFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let file = match std::fs::File::open(path_str) {
        Ok(f) => f,
        Err(_) => return ptr::null_mut(),
    };
    use polars::prelude::SerReader;
    match polars::prelude::JsonReader::new(file)
        .with_json_format(polars::prelude::JsonFormat::JsonLines)
        .finish()
    {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_to_string(df_ptr: *mut DataFrame) -> *const c_char {
    if df_ptr.is_null() {
        return ptr::null();
    }
    let df = unsafe { &*df_ptr };
    rust_string_to_ptr(format!("{}", df))
}

#[no_mangle]
pub extern "C" fn dataframe_shape(df_ptr: *mut DataFrame) -> Shape {
    if df_ptr.is_null() {
        Shape { rows: 0, cols: 0 }
    } else {
        let df = unsafe { &*df_ptr };
        let shape = df.shape();
        Shape {
            rows: shape.0,
            cols: shape.1,
        }
    }
}

#[no_mangle]
pub extern "C" fn series_make() -> *mut Series {
    let s = Series::new("example", &[1, 2, 3, 4]);
    let boxed_s = Box::new(s);
    Box::into_raw(boxed_s)
}

#[no_mangle]
pub extern "C" fn series_empty() -> *mut Series {
    Box::into_raw(Box::new(Series::new_empty("", &DataType::Int32)))
}

#[no_mangle]
pub extern "C" fn series_drop(s_ptr: *mut Series) {
    if !s_ptr.is_null() {
        unsafe { drop(Box::from_raw(s_ptr)) };
    }
}

#[no_mangle]
pub extern "C" fn series_name(s_ptr: *mut Series) -> *const c_char {
    if s_ptr.is_null() {
        return ptr::null();
    }

    unsafe { rust_string_to_ptr((&*s_ptr).name()) }
}

#[no_mangle]
pub extern "C" fn series_dtype(s_ptr: *mut Series) -> CompatDType {
    if s_ptr.is_null() {
        return CompatDType {
            tag: CompatDTypeTag::Unknown as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        };
    }

    unsafe { compat_dtype_from_polars((&*s_ptr).dtype()) }
}

#[no_mangle]
pub extern "C" fn series_rename(s_ptr: *mut Series, new_name: *const c_char) {
    if s_ptr.is_null() || new_name.is_null() {
        return;
    }

    unsafe {
        let s = &mut *s_ptr;
        let c_str = CStr::from_ptr(new_name);
        if let Ok(str_slice) = c_str.to_str() {
            s.rename(str_slice);
        }
    }
}

#[no_mangle]
pub extern "C" fn series_len(s_ptr: *mut Series) -> usize {
    if s_ptr.is_null() {
        0
    } else {
        unsafe {
            let s = &*s_ptr;
            s.len()
        }
    }
}

#[no_mangle]
pub extern "C" fn series_null_count(s_ptr: *mut Series) -> usize {
    if s_ptr.is_null() {
        0
    } else {
        unsafe {
            let s = &*s_ptr;
            s.null_count()
        }
    }
}

fn create_chunked_array_from_raw<T>(
    name: *const c_char,
    data: *const T::Native,
    length: usize,
) -> ChunkedArray<T>
where
    T: PolarsNumericType,
{
    let slice = unsafe { std::slice::from_raw_parts(data as *const _, length) };
    let vec = slice.to_vec();

    unsafe {
        if let Ok(name) = CStr::from_ptr(name).to_str() {
            ChunkedArray::from_vec(name, vec)
        } else {
            ChunkedArray::from_vec("", vec)
        }
    }
}

fn series_new<T>(
    name: *const c_char,
    data: *const T::Native,
    length: usize,
) -> *mut Series
where
    T: PolarsNumericType + Clone,
    ChunkedArray<T>: IntoSeries,
{
    if name.is_null() || data.is_null() {
        return ptr::null_mut();
    }

    let s = create_chunked_array_from_raw(name, data, length);
    Box::into_raw(Box::new(s.into()))
}

fn valid_slices<'a, T>(
    data: *const T,
    valid: *const u8,
    length: usize,
) -> Option<(&'a [T], &'a [u8])> {
    if (data.is_null() || valid.is_null()) && length != 0 {
        return None;
    }
    let values = if length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(data, length) }
    };
    let valid = if length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(valid, length) }
    };
    Some((values, valid))
}

macro_rules! series_new_opt_primitive {
    ($fn_name:ident, $ty:ty) => {
        #[no_mangle]
        pub extern "C" fn $fn_name(
            name: *const c_char,
            data: *const $ty,
            valid: *const u8,
            length: usize,
        ) -> *mut Series {
            if name.is_null() {
                return ptr::null_mut();
            }
            let Some((values, valid)) = valid_slices(data, valid, length)
            else {
                return ptr::null_mut();
            };
            let options: Vec<Option<$ty>> = values
                .iter()
                .zip(valid.iter())
                .map(
                    |(value, is_valid)| {
                        if *is_valid == 0 {
                            None
                        } else {
                            Some(*value)
                        }
                    },
                )
                .collect();
            Box::into_raw(Box::new(Series::new(name_from_ptr(name), options)))
        }
    };
}

#[no_mangle]
pub extern "C" fn series_new_i32(
    name: *const c_char,
    data: *const i32,
    length: usize,
) -> *mut Series {
    series_new::<Int32Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_i8(
    name: *const c_char,
    data: *const i8,
    length: usize,
) -> *mut Series {
    series_new::<Int8Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_i16(
    name: *const c_char,
    data: *const i16,
    length: usize,
) -> *mut Series {
    series_new::<Int16Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_f64(
    name: *const c_char,
    data: *const f64,
    length: usize,
) -> *mut Series {
    series_new::<Float64Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_f32(
    name: *const c_char,
    data: *const f32,
    length: usize,
) -> *mut Series {
    series_new::<Float32Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_i64(
    name: *const c_char,
    data: *const i64,
    length: usize,
) -> *mut Series {
    series_new::<Int64Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_u8(
    name: *const c_char,
    data: *const u8,
    length: usize,
) -> *mut Series {
    series_new::<UInt8Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_u16(
    name: *const c_char,
    data: *const u16,
    length: usize,
) -> *mut Series {
    series_new::<UInt16Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_u32(
    name: *const c_char,
    data: *const u32,
    length: usize,
) -> *mut Series {
    series_new::<UInt32Type>(name, data, length)
}

#[no_mangle]
pub extern "C" fn series_new_u64(
    name: *const c_char,
    data: *const u64,
    length: usize,
) -> *mut Series {
    series_new::<UInt64Type>(name, data, length)
}

series_new_opt_primitive!(series_new_opt_i8, i8);
series_new_opt_primitive!(series_new_opt_i16, i16);
series_new_opt_primitive!(series_new_opt_i32, i32);
series_new_opt_primitive!(series_new_opt_f32, f32);
series_new_opt_primitive!(series_new_opt_f64, f64);
series_new_opt_primitive!(series_new_opt_i64, i64);
series_new_opt_primitive!(series_new_opt_u8, u8);
series_new_opt_primitive!(series_new_opt_u16, u16);
series_new_opt_primitive!(series_new_opt_u32, u32);
series_new_opt_primitive!(series_new_opt_u64, u64);

#[no_mangle]
pub extern "C" fn series_new_bool(
    name: *const c_char,
    data: *const u8,
    length: usize,
) -> *mut Series {
    if name.is_null() || (data.is_null() && length != 0) {
        return ptr::null_mut();
    }
    let bools: Vec<bool> = if length == 0 {
        Vec::new()
    } else {
        unsafe { std::slice::from_raw_parts(data, length) }
            .iter()
            .map(|&b| b != 0)
            .collect()
    };
    let n = name_from_ptr(name);
    Box::into_raw(Box::new(Series::new(n, bools)))
}

#[no_mangle]
pub extern "C" fn series_new_opt_bool(
    name: *const c_char,
    data: *const u8,
    valid: *const u8,
    length: usize,
) -> *mut Series {
    if name.is_null() {
        return ptr::null_mut();
    }
    let Some((values, valid)) = valid_slices(data, valid, length) else {
        return ptr::null_mut();
    };
    let bools: Vec<Option<bool>> = values
        .iter()
        .zip(valid.iter())
        .map(|(value, is_valid)| {
            if *is_valid == 0 {
                None
            } else {
                Some(*value != 0)
            }
        })
        .collect();
    Box::into_raw(Box::new(Series::new(name_from_ptr(name), bools)))
}

fn name_from_ptr(p: *const c_char) -> &'static str {
    if p.is_null() {
        return "";
    }
    if let Ok(name) = unsafe { CStr::from_ptr(p).to_str() } {
        name
    } else {
        ""
    }
}

#[no_mangle]
pub extern "C" fn series_new_str(
    name: *const c_char,
    data: *const *const c_char,
    length: usize,
) -> *mut Series {
    if data.is_null() {
        return std::ptr::null_mut();
    }

    let slice: &[*const c_char] =
        unsafe { std::slice::from_raw_parts(data, length) };
    let vec: Vec<&str> = slice
        .iter()
        .map(|&ptr| unsafe { CStr::from_ptr(ptr).to_str().unwrap_or_default() })
        .collect();
    Box::into_raw(Box::new(Series::new(name_from_ptr(name), vec)))
}

#[no_mangle]
pub extern "C" fn series_new_opt_str(
    name: *const c_char,
    data: *const *const c_char,
    valid: *const u8,
    length: usize,
) -> *mut Series {
    if data.is_null() && length != 0 {
        return std::ptr::null_mut();
    }
    let Some((values, valid)) = valid_slices(data, valid, length) else {
        return ptr::null_mut();
    };
    let strings: Vec<Option<&str>> = values
        .iter()
        .zip(valid.iter())
        .map(|(value, is_valid)| {
            if *is_valid == 0 || value.is_null() {
                None
            } else {
                unsafe { CStr::from_ptr(*value).to_str().ok() }
            }
        })
        .collect();
    Box::into_raw(Box::new(Series::new(name_from_ptr(name), strings)))
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct YMDHMS {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub second: u32,
}

#[repr(C)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub struct CompatOptYMDHMS {
    pub valid: i32,
    pub value: YMDHMS,
}

impl CompatOptYMDHMS {
    const NONE: Self = Self {
        valid: 0,
        value: YMDHMS {
            year: 0,
            month: 0,
            day: 0,
            hour: 0,
            minute: 0,
            second: 0,
        },
    };

    fn some(v: YMDHMS) -> Self {
        Self { valid: 1, value: v }
    }
}

#[no_mangle]
pub extern "C" fn series_sum_i32(s_ptr: *mut Series) -> CompatOptI32 {
    if s_ptr.is_null() {
        return CompatOptI32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => CompatOptI32::from_option(ca.sum()),
        Err(_) => CompatOptI32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_sum_f64(s_ptr: *mut Series) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f64() {
        Ok(ca) => CompatOptF64::from_option(ca.sum()),
        Err(_) => CompatOptF64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_mean_f64(s_ptr: *mut Series) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f64() {
        Ok(ca) => CompatOptF64::from_option(ca.mean()),
        Err(_) => CompatOptF64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_max_f64(s_ptr: *mut Series) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f64() {
        Ok(ca) => CompatOptF64::from_option(ca.max()),
        Err(_) => CompatOptF64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_min_i32(s_ptr: *mut Series) -> CompatOptI32 {
    if s_ptr.is_null() {
        return CompatOptI32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => CompatOptI32::from_option(ca.min()),
        Err(_) => CompatOptI32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_max_i32(s_ptr: *mut Series) -> CompatOptI32 {
    if s_ptr.is_null() {
        return CompatOptI32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => CompatOptI32::from_option(ca.max()),
        Err(_) => CompatOptI32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_mean_i32(s_ptr: *mut Series) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => CompatOptF64::from_option(ca.mean()),
        Err(_) => CompatOptF64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_min_f64(s_ptr: *mut Series) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f64() {
        Ok(ca) => CompatOptF64::from_option(ca.min()),
        Err(_) => CompatOptF64::NONE,
    }
}

macro_rules! series_int_reductions {
    ($downcast:ident, $compat_opt:ident,
     $sum:ident, $min:ident, $max:ident, $mean:ident) => {
        #[no_mangle]
        pub extern "C" fn $sum(s_ptr: *mut Series) -> $compat_opt {
            if s_ptr.is_null() {
                return $compat_opt::NONE;
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => $compat_opt::from_option(ca.sum()),
                Err(_) => $compat_opt::NONE,
            }
        }

        #[no_mangle]
        pub extern "C" fn $min(s_ptr: *mut Series) -> $compat_opt {
            if s_ptr.is_null() {
                return $compat_opt::NONE;
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => $compat_opt::from_option(ca.min()),
                Err(_) => $compat_opt::NONE,
            }
        }

        #[no_mangle]
        pub extern "C" fn $max(s_ptr: *mut Series) -> $compat_opt {
            if s_ptr.is_null() {
                return $compat_opt::NONE;
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => $compat_opt::from_option(ca.max()),
                Err(_) => $compat_opt::NONE,
            }
        }

        #[no_mangle]
        pub extern "C" fn $mean(s_ptr: *mut Series) -> CompatOptF64 {
            if s_ptr.is_null() {
                return CompatOptF64::NONE;
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => CompatOptF64::from_option(ca.mean()),
                Err(_) => CompatOptF64::NONE,
            }
        }
    };
}

series_int_reductions!(
    i8,
    CompatOptI8,
    series_sum_i8,
    series_min_i8,
    series_max_i8,
    series_mean_i8
);
series_int_reductions!(
    i16,
    CompatOptI16,
    series_sum_i16,
    series_min_i16,
    series_max_i16,
    series_mean_i16
);
series_int_reductions!(
    i64,
    CompatOptI64,
    series_sum_i64,
    series_min_i64,
    series_max_i64,
    series_mean_i64
);
series_int_reductions!(
    u8,
    CompatOptU8,
    series_sum_u8,
    series_min_u8,
    series_max_u8,
    series_mean_u8
);
series_int_reductions!(
    u16,
    CompatOptU16,
    series_sum_u16,
    series_min_u16,
    series_max_u16,
    series_mean_u16
);
series_int_reductions!(
    u32,
    CompatOptU32,
    series_sum_u32,
    series_min_u32,
    series_max_u32,
    series_mean_u32
);
series_int_reductions!(
    u64,
    CompatOptU64,
    series_sum_u64,
    series_min_u64,
    series_max_u64,
    series_mean_u64
);
series_int_reductions!(
    f32,
    CompatOptF32,
    series_sum_f32,
    series_min_f32,
    series_max_f32,
    series_mean_f32
);

#[no_mangle]
pub extern "C" fn series_n_unique(s_ptr: *mut Series) -> usize {
    if s_ptr.is_null() {
        return 0;
    }
    let s = unsafe { &*s_ptr };
    s.n_unique().unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn series_head(s_ptr: *mut Series, n: usize) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.head(Some(n))))
}

#[no_mangle]
pub extern "C" fn series_tail(s_ptr: *mut Series, n: usize) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.tail(Some(n))))
}

#[no_mangle]
pub extern "C" fn series_slice(
    s_ptr: *mut Series,
    offset: i64,
    length: usize,
) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.slice(offset, length)))
}

#[no_mangle]
pub extern "C" fn series_reverse(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.reverse()))
}

#[no_mangle]
pub extern "C" fn series_drop_nulls(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    Box::into_raw(Box::new(s.drop_nulls()))
}

#[no_mangle]
pub extern "C" fn series_unique(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    match s.unique() {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_sort(
    s_ptr: *mut Series,
    descending: u8,
) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    let opts = SortOptions::default().with_order_descending(descending != 0);
    match s.sort_with(opts) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_new_ymdhms(
    name: *const c_char,
    data: *const YMDHMS,
    length: usize,
) -> *mut Series {
    if data.is_null() {
        std::ptr::null_mut()
    } else {
        let ymdhms_slice = unsafe { std::slice::from_raw_parts(data, length) };
        let naive_dates: Vec<NaiveDateTime> = ymdhms_slice
            .iter()
            .map(|ymdhms| {
                NaiveDate::from_ymd_opt(ymdhms.year, ymdhms.month, ymdhms.day)
                    .unwrap()
                    .and_hms_opt(ymdhms.hour, ymdhms.minute, ymdhms.second)
                    .unwrap()
            })
            .collect();
        Box::into_raw(Box::new(Series::new(name_from_ptr(name), naive_dates)))
    }
}

fn ymdhms_to_naive_datetime(ymdhms: &YMDHMS) -> Option<NaiveDateTime> {
    NaiveDate::from_ymd_opt(ymdhms.year, ymdhms.month, ymdhms.day).and_then(
        |date| date.and_hms_opt(ymdhms.hour, ymdhms.minute, ymdhms.second),
    )
}

#[no_mangle]
pub extern "C" fn series_new_opt_ymdhms(
    name: *const c_char,
    data: *const YMDHMS,
    valid: *const u8,
    length: usize,
) -> *mut Series {
    let Some((values, valid)) = valid_slices(data, valid, length) else {
        return ptr::null_mut();
    };
    let naive_dates =
        values.iter().zip(valid.iter()).map(|(ymdhms, is_valid)| {
            if *is_valid == 0 {
                None
            } else {
                ymdhms_to_naive_datetime(ymdhms)
            }
        });
    let ca = DatetimeChunked::from_naive_datetime_options(
        name_from_ptr(name),
        naive_dates,
        TimeUnit::Milliseconds,
    );
    Box::into_raw(Box::new(ca.into_series()))
}

#[no_mangle]
pub extern "C" fn series_ref_is_null(s_ptr: *mut Series, index: usize) -> i32 {
    if s_ptr.is_null() {
        return -1;
    }
    let s = unsafe { &*s_ptr };
    if index >= s.len() {
        return -1;
    }
    if s.null_count() == 0 {
        return 0;
    }
    if s.is_null().get(index).unwrap_or(false) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI32 {
    if s_ptr.is_null() {
        return CompatOptI32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => CompatOptI32::from_option(ca.get(index)),
        Err(_) => CompatOptI32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i8(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI8 {
    if s_ptr.is_null() {
        return CompatOptI8::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i8() {
        Ok(ca) => CompatOptI8::from_option(ca.get(index)),
        Err(_) => CompatOptI8::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i16(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI16 {
    if s_ptr.is_null() {
        return CompatOptI16::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i16() {
        Ok(ca) => CompatOptI16::from_option(ca.get(index)),
        Err(_) => CompatOptI16::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_i64(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    if s_ptr.is_null() {
        return CompatOptI64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.i64() {
        Ok(ca) => CompatOptI64::from_option(ca.get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u8(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU8 {
    if s_ptr.is_null() {
        return CompatOptU8::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u8() {
        Ok(ca) => CompatOptU8::from_option(ca.get(index)),
        Err(_) => CompatOptU8::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u16(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU16 {
    if s_ptr.is_null() {
        return CompatOptU16::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u16() {
        Ok(ca) => CompatOptU16::from_option(ca.get(index)),
        Err(_) => CompatOptU16::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU32 {
    if s_ptr.is_null() {
        return CompatOptU32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u32() {
        Ok(ca) => CompatOptU32::from_option(ca.get(index)),
        Err(_) => CompatOptU32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_u64(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptU64 {
    if s_ptr.is_null() {
        return CompatOptU64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.u64() {
        Ok(ca) => CompatOptU64::from_option(ca.get(index)),
        Err(_) => CompatOptU64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_f32(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptF32 {
    if s_ptr.is_null() {
        return CompatOptF32::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f32() {
        Ok(ca) => CompatOptF32::from_option(ca.get(index)),
        Err(_) => CompatOptF32::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_f64(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.f64() {
        Ok(ca) => CompatOptF64::from_option(ca.get(index)),
        Err(_) => CompatOptF64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_bool(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptBool {
    if s_ptr.is_null() {
        return CompatOptBool::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.bool() {
        Ok(ca) => CompatOptBool::from_option(ca.get(index)),
        Err(_) => CompatOptBool::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_str(
    s_ptr: *mut Series,
    index: usize,
) -> *const c_char {
    if s_ptr.is_null() {
        return ptr::null();
    }
    let s = unsafe { &*s_ptr };
    match s.str() {
        Ok(ca) => ca.get(index).map(rust_string_to_ptr).unwrap_or(ptr::null()),
        Err(_) => ptr::null(),
    }
}

fn date_days_to_ymd(days: i32) -> Option<YMD> {
    NaiveDate::from_ymd_opt(1970, 1, 1)
        .and_then(|epoch| {
            epoch.checked_add_signed(ChronoDuration::days(days as i64))
        })
        .map(|date| YMD {
            year: date.year(),
            month: date.month(),
            day: date.day(),
        })
}

#[no_mangle]
pub extern "C" fn series_ref_date(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptYMD {
    if s_ptr.is_null() {
        return CompatOptYMD::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.date() {
        Ok(ca) => ca
            .get(index)
            .and_then(date_days_to_ymd)
            .map(CompatOptYMD::some)
            .unwrap_or(CompatOptYMD::NONE),
        Err(_) => CompatOptYMD::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_duration(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    if s_ptr.is_null() {
        return CompatOptI64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.duration() {
        Ok(ca) => CompatOptI64::from_option(ca.get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_ref_time(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptI64 {
    if s_ptr.is_null() {
        return CompatOptI64::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.time() {
        Ok(ca) => CompatOptI64::from_option(ca.get(index)),
        Err(_) => CompatOptI64::NONE,
    }
}

fn datetime_value_to_ymdhms(
    value: i64,
    time_unit: &TimeUnit,
) -> Option<YMDHMS> {
    let (secs, nanos) = match time_unit {
        TimeUnit::Nanoseconds => (
            value.div_euclid(1_000_000_000),
            value.rem_euclid(1_000_000_000) as u32,
        ),
        TimeUnit::Microseconds => (
            value.div_euclid(1_000_000),
            (value.rem_euclid(1_000_000) * 1_000) as u32,
        ),
        TimeUnit::Milliseconds => (
            value.div_euclid(1_000),
            (value.rem_euclid(1_000) * 1_000_000) as u32,
        ),
    };
    DateTime::from_timestamp(secs, nanos)
        .map(|dt| dt.naive_utc())
        .map(|dt| YMDHMS {
            year: dt.year(),
            month: dt.month(),
            day: dt.day(),
            hour: dt.hour(),
            minute: dt.minute(),
            second: dt.second(),
        })
}

#[no_mangle]
pub extern "C" fn series_ref_ymdhms(
    s_ptr: *mut Series,
    index: usize,
) -> CompatOptYMDHMS {
    if s_ptr.is_null() {
        return CompatOptYMDHMS::NONE;
    }
    let s = unsafe { &*s_ptr };
    match s.datetime() {
        Ok(ca) => ca
            .get(index)
            .and_then(|value| datetime_value_to_ymdhms(value, &ca.time_unit()))
            .map(CompatOptYMDHMS::some)
            .unwrap_or(CompatOptYMDHMS::NONE),
        Err(_) => CompatOptYMDHMS::NONE,
    }
}

#[no_mangle]
pub extern "C" fn series_cast(
    s_ptr: *mut Series,
    target: CompatDType,
) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let dt = match polars_dtype_from_compat(&target) {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    let s = unsafe { &*s_ptr };
    match s.cast(&dt) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_std(s_ptr: *mut Series, ddof: u8) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    CompatOptF64::from_option(s.std(ddof))
}

#[no_mangle]
pub extern "C" fn series_var(s_ptr: *mut Series, ddof: u8) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let s = unsafe { &*s_ptr };
    CompatOptF64::from_option(s.var(ddof))
}

fn series_cmp_result<F>(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
    f: F,
) -> *mut Series
where
    F: FnOnce(&Series, &Series) -> PolarsResult<BooleanChunked>,
{
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    match f(left, right) {
        Ok(out) => Box::into_raw(Box::new(out.into_series())),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_eq(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.equal(right))
}

#[no_mangle]
pub extern "C" fn series_ne(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.not_equal(right))
}

#[no_mangle]
pub extern "C" fn series_gt(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.gt(right))
}

#[no_mangle]
pub extern "C" fn series_ge(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.gt_eq(right))
}

#[no_mangle]
pub extern "C" fn series_lt(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.lt(right))
}

#[no_mangle]
pub extern "C" fn series_le(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_cmp_result(left_ptr, right_ptr, |left, right| left.lt_eq(right))
}

fn series_arith_result<F>(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
    f: F,
) -> *mut Series
where
    F: FnOnce(&Series, &Series) -> PolarsResult<Series>,
{
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { &*left_ptr };
    let right = unsafe { &*right_ptr };
    match f(left, right) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn series_add(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Add::add(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_sub(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Sub::sub(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_mul(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Mul::mul(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_div(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Div::div(left, right)
    })
}

#[no_mangle]
pub extern "C" fn series_mod(
    left_ptr: *mut Series,
    right_ptr: *mut Series,
) -> *mut Series {
    series_arith_result(left_ptr, right_ptr, |left, right| {
        std::ops::Rem::rem(left, right)
    })
}

macro_rules! arith_scalar {
    ($name:ident, $op:path, $downcast:ident, $rhs_ty:ty) => {
        #[no_mangle]
        pub extern "C" fn $name(
            s_ptr: *mut Series,
            rhs: $rhs_ty,
        ) -> *mut Series {
            if s_ptr.is_null() {
                return ptr::null_mut();
            }
            let s = unsafe { &*s_ptr };
            match s.$downcast() {
                Ok(ca) => Box::into_raw(Box::new($op(ca, rhs).into_series())),
                Err(_) => ptr::null_mut(),
            }
        }
    };
}

macro_rules! arith_scalar_family {
    ($downcast:ident, $rhs_ty:ty,
     $add:ident, $sub:ident, $mul:ident, $div:ident, $rem:ident) => {
        arith_scalar!($add, std::ops::Add::add, $downcast, $rhs_ty);
        arith_scalar!($sub, std::ops::Sub::sub, $downcast, $rhs_ty);
        arith_scalar!($mul, std::ops::Mul::mul, $downcast, $rhs_ty);
        arith_scalar!($div, std::ops::Div::div, $downcast, $rhs_ty);
        arith_scalar!($rem, std::ops::Rem::rem, $downcast, $rhs_ty);
    };
}

arith_scalar_family!(
    i32,
    i32,
    series_add_i32,
    series_sub_i32,
    series_mul_i32,
    series_div_i32,
    series_mod_i32
);
arith_scalar_family!(
    i64,
    i64,
    series_add_i64,
    series_sub_i64,
    series_mul_i64,
    series_div_i64,
    series_mod_i64
);
arith_scalar_family!(
    u32,
    u32,
    series_add_u32,
    series_sub_u32,
    series_mul_u32,
    series_div_u32,
    series_mod_u32
);
arith_scalar_family!(
    u64,
    u64,
    series_add_u64,
    series_sub_u64,
    series_mul_u64,
    series_div_u64,
    series_mod_u64
);
arith_scalar_family!(
    f64,
    f64,
    series_add_f64,
    series_sub_f64,
    series_mul_f64,
    series_div_f64,
    series_mod_f64
);

// ===== Track A: Expr / Lazy DSL =====

#[no_mangle]
pub extern "C" fn expr_drop(e: *mut Expr) {
    if !e.is_null() {
        unsafe { drop(Box::from_raw(e)) };
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_drop(lf: *mut LazyFrame) {
    if !lf.is_null() {
        unsafe { drop(Box::from_raw(lf)) };
    }
}

#[no_mangle]
pub extern "C" fn expr_col(name: *const c_char) -> *mut Expr {
    if name.is_null() {
        return ptr::null_mut();
    }
    let n = match unsafe { CStr::from_ptr(name).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    Box::into_raw(Box::new(col(n)))
}

#[no_mangle]
pub extern "C" fn expr_lit_i32(v: i32) -> *mut Expr {
    Box::into_raw(Box::new(lit(v)))
}

#[no_mangle]
pub extern "C" fn expr_lit_i64(v: i64) -> *mut Expr {
    Box::into_raw(Box::new(lit(v)))
}

#[no_mangle]
pub extern "C" fn expr_lit_f64(v: f64) -> *mut Expr {
    Box::into_raw(Box::new(lit(v)))
}

#[no_mangle]
pub extern "C" fn expr_lit_bool(v: u8) -> *mut Expr {
    Box::into_raw(Box::new(lit(v != 0)))
}

#[no_mangle]
pub extern "C" fn expr_lit_str(v: *const c_char) -> *mut Expr {
    if v.is_null() {
        return ptr::null_mut();
    }
    let s = match unsafe { CStr::from_ptr(v).to_str() } {
        Ok(s) => s.to_string(),
        Err(_) => return ptr::null_mut(),
    };
    Box::into_raw(Box::new(lit(s)))
}

#[no_mangle]
pub extern "C" fn expr_alias(e: *const Expr, name: *const c_char) -> *mut Expr {
    if e.is_null() || name.is_null() {
        return ptr::null_mut();
    }
    let n = match unsafe { CStr::from_ptr(name).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let inner = unsafe { (*e).clone() };
    Box::into_raw(Box::new(inner.alias(n)))
}

#[no_mangle]
pub extern "C" fn dataframe_lazy(df: *mut DataFrame) -> *mut LazyFrame {
    if df.is_null() {
        return ptr::null_mut();
    }
    let cloned = unsafe { (*df).clone() };
    Box::into_raw(Box::new(cloned.lazy()))
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_csv(path: *const c_char) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match polars::prelude::LazyCsvReader::new(path_str).finish() {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_csv_options(
    path: *const c_char,
    has_header: u8,
    separator: u8,
    skip_rows: usize,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let mut reader = polars::prelude::LazyCsvReader::new(path_str)
        .with_has_header(has_header != 0)
        .with_separator(separator)
        .with_skip_rows(skip_rows);
    if has_n_rows != 0 {
        reader = reader.with_n_rows(Some(n_rows));
    }
    match reader.finish() {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet(
    path: *const c_char,
) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    match LazyFrame::scan_parquet(path_str, Default::default()) {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn lazyframe_scan_parquet_options(
    path: *const c_char,
    has_n_rows: u8,
    n_rows: usize,
) -> *mut LazyFrame {
    if path.is_null() {
        return ptr::null_mut();
    }
    let path_str = match unsafe { CStr::from_ptr(path).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let mut args = ScanArgsParquet::default();
    if has_n_rows != 0 {
        args.n_rows = Some(n_rows);
    }
    match LazyFrame::scan_parquet(path_str, args) {
        Ok(lf) => Box::into_raw(Box::new(lf)),
        Err(_) => ptr::null_mut(),
    }
}

unsafe fn collect_exprs(
    ptrs: *const *const Expr,
    n: usize,
) -> Option<Vec<Expr>> {
    if n == 0 {
        return Some(Vec::new());
    }
    if ptrs.is_null() {
        return None;
    }
    let slice = std::slice::from_raw_parts(ptrs, n);
    let mut out = Vec::with_capacity(n);
    for &p in slice {
        if p.is_null() {
            return None;
        }
        out.push((*p).clone());
    }
    Some(out)
}

#[no_mangle]
pub extern "C" fn lazyframe_with_columns(
    lf: *mut LazyFrame,
    expr_ptrs: *const *const Expr,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let exprs = match unsafe { collect_exprs(expr_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.with_columns(exprs)))
}

#[no_mangle]
pub extern "C" fn lazyframe_collect(lf: *mut LazyFrame) -> *mut DataFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let owned = unsafe { (*lf).clone() };
    match owned.collect() {
        Ok(df) => Box::into_raw(Box::new(df)),
        Err(_) => ptr::null_mut(),
    }
}

macro_rules! expr_binop {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(a: *const Expr, b: *const Expr) -> *mut Expr {
            if a.is_null() || b.is_null() {
                return ptr::null_mut();
            }
            let aa = unsafe { (*a).clone() };
            let bb = unsafe { (*b).clone() };
            let f: fn(Expr, Expr) -> Expr = $build;
            Box::into_raw(Box::new(f(aa, bb)))
        }
    };
}

expr_binop!(expr_add, |a, b| a + b);
expr_binop!(expr_sub, |a, b| a - b);
expr_binop!(expr_mul, |a, b| a * b);
expr_binop!(expr_div, |a, b| a / b);
expr_binop!(expr_mod, |a, b| a % b);

expr_binop!(expr_gt, |a, b| a.gt(b));
expr_binop!(expr_lt, |a, b| a.lt(b));
expr_binop!(expr_ge, |a, b| a.gt_eq(b));
expr_binop!(expr_le, |a, b| a.lt_eq(b));
expr_binop!(expr_eq, |a, b| a.eq(b));
expr_binop!(expr_ne, |a, b| a.neq(b));

expr_binop!(expr_and, |a, b| a.and(b));
expr_binop!(expr_or, |a, b| a.or(b));
expr_binop!(expr_xor, |a, b| a.xor(b));

/// Conditional expression: parallel `conds` / `vals` arrays of length `n`
/// plus a final `otherwise`. Lowered as nested
/// `when(c0).then(v0).otherwise(when(c1).then(v1).otherwise(... otherwise)))`,
/// which is semantically the chained `when().then()...otherwise()` form.
#[no_mangle]
pub extern "C" fn expr_when_then(
    conds: *const *const Expr,
    vals: *const *const Expr,
    n: usize,
    otherwise: *const Expr,
) -> *mut Expr {
    if conds.is_null() || vals.is_null() || otherwise.is_null() || n == 0 {
        return ptr::null_mut();
    }
    let conds = unsafe { std::slice::from_raw_parts(conds, n) };
    let vals = unsafe { std::slice::from_raw_parts(vals, n) };
    if conds.iter().chain(vals.iter()).any(|p| p.is_null()) {
        return ptr::null_mut();
    }
    let mut acc = unsafe { (*otherwise).clone() };
    for i in (0..n).rev() {
        let c = unsafe { (*conds[i]).clone() };
        let v = unsafe { (*vals[i]).clone() };
        acc = when(c).then(v).otherwise(acc);
    }
    Box::into_raw(Box::new(acc))
}

#[no_mangle]
pub extern "C" fn expr_str_contains(
    e: *const Expr,
    pat: *const Expr,
    strict: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().contains(pp, strict != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_starts_with(
    e: *const Expr,
    prefix: *const Expr,
) -> *mut Expr {
    if e.is_null() || prefix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*prefix).clone() };
    Box::into_raw(Box::new(ee.str().starts_with(pp)))
}

#[no_mangle]
pub extern "C" fn expr_str_ends_with(
    e: *const Expr,
    suffix: *const Expr,
) -> *mut Expr {
    if e.is_null() || suffix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let ss = unsafe { (*suffix).clone() };
    Box::into_raw(Box::new(ee.str().ends_with(ss)))
}

#[no_mangle]
pub extern "C" fn expr_str_to_lowercase(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().to_lowercase()))
}

#[no_mangle]
pub extern "C" fn expr_str_to_uppercase(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().to_uppercase()))
}

#[no_mangle]
pub extern "C" fn expr_str_replace(
    e: *const Expr,
    pat: *const Expr,
    value: *const Expr,
    literal: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() || value.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    let vv = unsafe { (*value).clone() };
    Box::into_raw(Box::new(ee.str().replace(pp, vv, literal != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_replace_all(
    e: *const Expr,
    pat: *const Expr,
    value: *const Expr,
    literal: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() || value.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    let vv = unsafe { (*value).clone() };
    Box::into_raw(Box::new(ee.str().replace_all(pp, vv, literal != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_extract(
    e: *const Expr,
    pat: *const Expr,
    group_index: usize,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().extract(pp, group_index)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars(
    e: *const Expr,
    chars: *const Expr,
) -> *mut Expr {
    if e.is_null() || chars.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let cc = unsafe { (*chars).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars(cc)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_start(
    e: *const Expr,
    chars: *const Expr,
) -> *mut Expr {
    if e.is_null() || chars.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let cc = unsafe { (*chars).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_start(cc)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_end(
    e: *const Expr,
    chars: *const Expr,
) -> *mut Expr {
    if e.is_null() || chars.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let cc = unsafe { (*chars).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_end(cc)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_whitespace(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars(Expr::default())))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_start_whitespace(
    e: *const Expr,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_start(Expr::default())))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_chars_end_whitespace(
    e: *const Expr,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().strip_chars_end(Expr::default())))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_prefix(
    e: *const Expr,
    prefix: *const Expr,
) -> *mut Expr {
    if e.is_null() || prefix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*prefix).clone() };
    Box::into_raw(Box::new(ee.str().strip_prefix(pp)))
}

#[no_mangle]
pub extern "C" fn expr_str_strip_suffix(
    e: *const Expr,
    suffix: *const Expr,
) -> *mut Expr {
    if e.is_null() || suffix.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let ss = unsafe { (*suffix).clone() };
    Box::into_raw(Box::new(ee.str().strip_suffix(ss)))
}

#[no_mangle]
pub extern "C" fn expr_str_len_bytes(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().len_bytes()))
}

#[no_mangle]
pub extern "C" fn expr_str_len_chars(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.str().len_chars()))
}

#[no_mangle]
pub extern "C" fn expr_str_slice(
    e: *const Expr,
    offset: *const Expr,
    length: *const Expr,
) -> *mut Expr {
    if e.is_null() || offset.is_null() || length.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let oo = unsafe { (*offset).clone() };
    let ll = unsafe { (*length).clone() };
    Box::into_raw(Box::new(ee.str().slice(oo, ll)))
}

#[no_mangle]
pub extern "C" fn expr_str_head(e: *const Expr, n: *const Expr) -> *mut Expr {
    if e.is_null() || n.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let nn = unsafe { (*n).clone() };
    Box::into_raw(Box::new(ee.str().head(nn)))
}

#[no_mangle]
pub extern "C" fn expr_str_tail(e: *const Expr, n: *const Expr) -> *mut Expr {
    if e.is_null() || n.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let nn = unsafe { (*n).clone() };
    Box::into_raw(Box::new(ee.str().tail(nn)))
}

#[no_mangle]
pub extern "C" fn expr_str_find(
    e: *const Expr,
    pat: *const Expr,
    strict: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().find(pp, strict != 0)))
}

#[no_mangle]
pub extern "C" fn expr_str_find_literal(
    e: *const Expr,
    pat: *const Expr,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().find_literal(pp)))
}

#[no_mangle]
pub extern "C" fn expr_str_count_matches(
    e: *const Expr,
    pat: *const Expr,
    literal: u8,
) -> *mut Expr {
    if e.is_null() || pat.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let pp = unsafe { (*pat).clone() };
    Box::into_raw(Box::new(ee.str().count_matches(pp, literal != 0)))
}

fn strptime_options(
    format: Option<String>,
    strict: u8,
    exact: u8,
    cache: u8,
) -> StrptimeOptions {
    StrptimeOptions {
        format,
        strict: strict != 0,
        exact: exact != 0,
        cache: cache != 0,
    }
}

fn c_string_option(format: *const c_char, has_format: u8) -> Option<String> {
    if has_format == 0 || format.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(format).to_str().ok().map(String::from) }
}

fn compat_time_unit_from_code(unit: i32) -> Option<TimeUnit> {
    match unit {
        x if x == CompatTimeUnit::Nanoseconds as i32 => {
            Some(TimeUnit::Nanoseconds)
        }
        x if x == CompatTimeUnit::Microseconds as i32 => {
            Some(TimeUnit::Microseconds)
        }
        x if x == CompatTimeUnit::Milliseconds as i32 => {
            Some(TimeUnit::Milliseconds)
        }
        _ => None,
    }
}

#[no_mangle]
pub extern "C" fn expr_str_to_date(
    e: *const Expr,
    format: *const c_char,
    has_format: u8,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let options = strptime_options(
        c_string_option(format, has_format),
        strict,
        exact,
        cache,
    );
    Box::into_raw(Box::new(ee.str().to_date(options)))
}

#[no_mangle]
pub extern "C" fn expr_str_to_datetime(
    e: *const Expr,
    format: *const c_char,
    has_format: u8,
    time_unit: i32,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let Some(tu) = compat_time_unit_from_code(time_unit) else {
        return ptr::null_mut();
    };
    let ee = unsafe { (*e).clone() };
    let options = strptime_options(
        c_string_option(format, has_format),
        strict,
        exact,
        cache,
    );
    Box::into_raw(Box::new(ee.str().to_datetime(
        Some(tu),
        None,
        options,
        lit("raise"),
    )))
}

#[no_mangle]
pub extern "C" fn expr_str_to_time(
    e: *const Expr,
    format: *const c_char,
    has_format: u8,
    strict: u8,
    exact: u8,
    cache: u8,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let options = strptime_options(
        c_string_option(format, has_format),
        strict,
        exact,
        cache,
    );
    Box::into_raw(Box::new(ee.str().to_time(options)))
}

#[no_mangle]
pub extern "C" fn expr_dt_year(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().year()))
}

#[no_mangle]
pub extern "C" fn expr_dt_month(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().month()))
}

#[no_mangle]
pub extern "C" fn expr_dt_day(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().day()))
}

#[no_mangle]
pub extern "C" fn expr_dt_hour(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().hour()))
}

#[no_mangle]
pub extern "C" fn expr_dt_minute(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().minute()))
}

#[no_mangle]
pub extern "C" fn expr_dt_second(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().second()))
}

#[no_mangle]
pub extern "C" fn expr_dt_iso_year(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().iso_year()))
}

#[no_mangle]
pub extern "C" fn expr_dt_quarter(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().quarter()))
}

#[no_mangle]
pub extern "C" fn expr_dt_week(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().week()))
}

#[no_mangle]
pub extern "C" fn expr_dt_weekday(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().weekday()))
}

#[no_mangle]
pub extern "C" fn expr_dt_ordinal_day(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().ordinal_day()))
}

#[no_mangle]
pub extern "C" fn expr_dt_is_leap_year(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().is_leap_year()))
}

#[no_mangle]
pub extern "C" fn expr_dt_date(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().date()))
}

#[no_mangle]
pub extern "C" fn expr_dt_time(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().time()))
}

#[no_mangle]
pub extern "C" fn expr_dt_millisecond(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().millisecond()))
}

#[no_mangle]
pub extern "C" fn expr_dt_microsecond(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().microsecond()))
}

#[no_mangle]
pub extern "C" fn expr_dt_nanosecond(e: *const Expr) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().nanosecond()))
}

#[no_mangle]
pub extern "C" fn expr_dt_timestamp(e: *const Expr, unit: i32) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let tu = match unit {
        x if x == CompatTimeUnit::Nanoseconds as i32 => TimeUnit::Nanoseconds,
        x if x == CompatTimeUnit::Microseconds as i32 => TimeUnit::Microseconds,
        x if x == CompatTimeUnit::Milliseconds as i32 => TimeUnit::Milliseconds,
        _ => return ptr::null_mut(),
    };
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().timestamp(tu)))
}

#[no_mangle]
pub extern "C" fn expr_dt_strftime(
    e: *const Expr,
    format: *const c_char,
) -> *mut Expr {
    if e.is_null() || format.is_null() {
        return ptr::null_mut();
    }
    let fmt = match unsafe { CStr::from_ptr(format).to_str() } {
        Ok(s) => s,
        Err(_) => return ptr::null_mut(),
    };
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.dt().strftime(fmt)))
}

#[no_mangle]
pub extern "C" fn expr_dt_truncate(
    e: *const Expr,
    every: *const Expr,
) -> *mut Expr {
    if e.is_null() || every.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let ev = unsafe { (*every).clone() };
    Box::into_raw(Box::new(ee.dt().truncate(ev)))
}

macro_rules! expr_unop {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(e: *const Expr) -> *mut Expr {
            if e.is_null() {
                return ptr::null_mut();
            }
            let ee = unsafe { (*e).clone() };
            let f: fn(Expr) -> Expr = $build;
            Box::into_raw(Box::new(f(ee)))
        }
    };
}

/// Unary aggregations that take a `ddof: u8` parameter (std, var).
macro_rules! expr_unop_u8 {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(e: *const Expr, arg: u8) -> *mut Expr {
            if e.is_null() {
                return ptr::null_mut();
            }
            let ee = unsafe { (*e).clone() };
            let f: fn(Expr, u8) -> Expr = $build;
            Box::into_raw(Box::new(f(ee, arg)))
        }
    };
}

expr_unop!(expr_not, |e| e.not());
expr_unop!(expr_neg, |e| -e);
expr_unop!(expr_is_null, |e| e.is_null());
expr_unop!(expr_is_not_null, |e| e.is_not_null());

// Null / NaN handling.
expr_unop!(expr_drop_nulls, |e| e.drop_nulls());
expr_unop!(expr_drop_nans, |e| e.drop_nans());
expr_unop!(expr_is_nan, |e| e.is_nan());
expr_unop!(expr_is_not_nan, |e| e.is_not_nan());
expr_unop!(expr_is_finite, |e| e.is_finite());
expr_unop!(expr_is_infinite, |e| e.is_infinite());
expr_binop!(expr_fill_null, |a, b| a.fill_null(b));
expr_binop!(expr_fill_nan, |a, b| a.fill_nan(b));

// ----- membership / distinct predicates -----

/// Build a literal Expr from a Series (consumes nothing — clones the
/// Series). Useful as the right-hand side of `is_in`.
#[no_mangle]
pub extern "C" fn expr_lit_series(s: *const Series) -> *mut Expr {
    if s.is_null() {
        return ptr::null_mut();
    }
    let ss = unsafe { (*s).clone() };
    Box::into_raw(Box::new(lit(ss)))
}

expr_binop!(expr_is_in, |a, b| a.is_in(b));
expr_unop!(expr_is_unique, |e| e.is_unique());
expr_unop!(expr_is_duplicated, |e| e.is_duplicated());
expr_unop!(expr_is_first_distinct, |e| e.is_first_distinct());
expr_unop!(expr_is_last_distinct, |e| e.is_last_distinct());

/// `is_between` with a `closed` selector: 0 = both, 1 = left, 2 = right,
/// 3 = none (any other value treated as `both`).
#[no_mangle]
pub extern "C" fn expr_is_between(
    e: *const Expr,
    lower: *const Expr,
    upper: *const Expr,
    closed: u8,
) -> *mut Expr {
    if e.is_null() || lower.is_null() || upper.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lo = unsafe { (*lower).clone() };
    let hi = unsafe { (*upper).clone() };
    let c = match closed {
        1 => ClosedInterval::Left,
        2 => ClosedInterval::Right,
        3 => ClosedInterval::None,
        _ => ClosedInterval::Both,
    };
    Box::into_raw(Box::new(ee.is_between(lo, hi, c)))
}

#[no_mangle]
pub extern "C" fn expr_forward_fill(
    e: *const Expr,
    has_limit: u8,
    limit: u32,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lim = if has_limit != 0 { Some(limit) } else { None };
    Box::into_raw(Box::new(ee.forward_fill(lim)))
}

#[no_mangle]
pub extern "C" fn expr_backward_fill(
    e: *const Expr,
    has_limit: u8,
    limit: u32,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lim = if has_limit != 0 { Some(limit) } else { None };
    Box::into_raw(Box::new(ee.backward_fill(lim)))
}

// Aggregations: collapse a column to a single value when used inside
// .agg(...), or to a length-1 result when used at the top level.
expr_unop!(expr_sum, |e| e.sum());
expr_unop!(expr_mean, |e| e.mean());
expr_unop!(expr_min, |e| e.min());
expr_unop!(expr_max, |e| e.max());
expr_unop!(expr_count, |e| e.count());
expr_unop!(expr_n_unique, |e| e.n_unique());
expr_unop!(expr_first, |e| e.first());
expr_unop!(expr_last, |e| e.last());
expr_unop!(expr_median, |e| e.median());

// std / var carry a ddof parameter (degrees-of-freedom adjustment);
// matches polars and pandas defaults of 1 on the Racket side.
expr_unop_u8!(expr_std, |e, ddof| e.std(ddof));
expr_unop_u8!(expr_var, |e, ddof| e.var(ddof));

// ----- element-wise math -----

/// Unary op carrying a single `u32` extra arg (e.g. round's decimal count).
macro_rules! expr_unop_u32 {
    ($name:ident, $build:expr) => {
        #[no_mangle]
        pub extern "C" fn $name(e: *const Expr, arg: u32) -> *mut Expr {
            if e.is_null() {
                return ptr::null_mut();
            }
            let ee = unsafe { (*e).clone() };
            let f: fn(Expr, u32) -> Expr = $build;
            Box::into_raw(Box::new(f(ee, arg)))
        }
    };
}

expr_unop!(expr_abs, |e| e.abs());
expr_unop!(expr_sign, |e| e.sign());
expr_unop!(expr_floor, |e| e.floor());
expr_unop!(expr_ceil, |e| e.ceil());
expr_unop!(expr_sqrt, |e| e.sqrt());
expr_unop!(expr_exp, |e| e.exp());
expr_unop!(expr_log1p, |e| e.log1p());
expr_unop_u32!(expr_round, |e, decimals| e.round(decimals));
expr_binop!(expr_pow, |a, b| a.pow(b));

#[no_mangle]
pub extern "C" fn expr_log(e: *const Expr, base: f64) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.log(base)))
}

/// Clip values into `[min, max]`. Either bound may be absent (`has_*` == 0),
/// in which case the one-sided `clip_min` / `clip_max` is used (or the
/// identity expression when both are absent).
#[no_mangle]
pub extern "C" fn expr_clip(
    e: *const Expr,
    has_min: u8,
    min: *const Expr,
    has_max: u8,
    max: *const Expr,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let lo = if has_min != 0 {
        if min.is_null() {
            return ptr::null_mut();
        }
        Some(unsafe { (*min).clone() })
    } else {
        None
    };
    let hi = if has_max != 0 {
        if max.is_null() {
            return ptr::null_mut();
        }
        Some(unsafe { (*max).clone() })
    } else {
        None
    };
    let out = match (lo, hi) {
        (Some(l), Some(h)) => ee.clip(l, h),
        (Some(l), None) => ee.clip_min(l),
        (None, Some(h)) => ee.clip_max(h),
        (None, None) => ee,
    };
    Box::into_raw(Box::new(out))
}

#[no_mangle]
pub extern "C" fn lazyframe_filter(
    lf: *mut LazyFrame,
    predicate: *const Expr,
) -> *mut LazyFrame {
    if lf.is_null() || predicate.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    let p = unsafe { (*predicate).clone() };
    Box::into_raw(Box::new(lf_ref.filter(p)))
}

#[no_mangle]
pub extern "C" fn lazyframe_select(
    lf: *mut LazyFrame,
    expr_ptrs: *const *const Expr,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let exprs = match unsafe { collect_exprs(expr_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.select(exprs)))
}

#[no_mangle]
pub extern "C" fn expr_over(
    e: *const Expr,
    partition_ptrs: *const *const Expr,
    n: usize,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let parts = match unsafe { collect_exprs(partition_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let inner = unsafe { (*e).clone() };
    Box::into_raw(Box::new(inner.over(parts)))
}

#[no_mangle]
pub extern "C" fn expr_sort(e: *const Expr, descending: u8) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let inner = unsafe { (*e).clone() };
    let opts = SortOptions::default().with_order_descending(descending != 0);
    Box::into_raw(Box::new(inner.sort(opts)))
}

// LazyGroupBy::agg consumes self and LazyGroupBy is not Clone, which
// breaks the Racket allocator/deallocator round-tripping pattern.  Fold
// group_by + agg into a single FFI call so the intermediate state never
// crosses the boundary.
#[no_mangle]
pub extern "C" fn lazyframe_group_by_agg(
    lf: *mut LazyFrame,
    key_ptrs: *const *const Expr,
    n_keys: usize,
    agg_ptrs: *const *const Expr,
    n_aggs: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let keys = match unsafe { collect_exprs(key_ptrs, n_keys) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let aggs = match unsafe { collect_exprs(agg_ptrs, n_aggs) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.group_by(keys).agg(aggs)))
}

// ===== Phase A6: more LazyFrame ops (sort / unique / drop_nulls) =====

#[no_mangle]
pub extern "C" fn lazyframe_sort(
    lf: *mut LazyFrame,
    by_ptrs: *const *const c_char,
    descending_ptr: *const u8,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let names = match unsafe { collect_c_strings(by_ptrs, n) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let descending: Vec<bool> = if n == 0 {
        Vec::new()
    } else if descending_ptr.is_null() {
        vec![false; n]
    } else {
        unsafe { std::slice::from_raw_parts(descending_ptr, n) }
            .iter()
            .map(|&b| b != 0)
            .collect()
    };
    let by_exprs: Vec<Expr> = names.iter().map(|n| col(n)).collect();
    let opts =
        SortMultipleOptions::new().with_order_descending_multi(descending);
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.sort_by_exprs(by_exprs, opts)))
}

#[no_mangle]
pub extern "C" fn lazyframe_unique(lf: *mut LazyFrame) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(
        lf_ref.unique(None, polars::prelude::UniqueKeepStrategy::Any),
    ))
}

#[no_mangle]
pub extern "C" fn lazyframe_drop_nulls(lf: *mut LazyFrame) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    let subset: Option<Vec<Expr>> = None;
    Box::into_raw(Box::new(lf_ref.drop_nulls(subset)))
}

// ===== Phase A7: lazy head / tail / slice =====

#[no_mangle]
pub extern "C" fn lazyframe_head(
    lf: *mut LazyFrame,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.limit(n as u32)))
}

#[no_mangle]
pub extern "C" fn lazyframe_tail(
    lf: *mut LazyFrame,
    n: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.tail(n as u32)))
}

#[no_mangle]
pub extern "C" fn lazyframe_slice(
    lf: *mut LazyFrame,
    offset: i64,
    length: usize,
) -> *mut LazyFrame {
    if lf.is_null() {
        return ptr::null_mut();
    }
    let lf_ref = unsafe { (*lf).clone() };
    Box::into_raw(Box::new(lf_ref.slice(offset, length as u32)))
}

// ===== Phase A8: lazy join =====
//
// Mirrors the eager `dataframe_join` ABI exactly: same `CompatJoinKind`
// tags, same packed left/right key-name arrays.  Cross uses
// `LazyFrame::cross_join`; inner/left/outer go through `.join` with
// per-side `Vec<Expr>` built from `col(name)`.

#[no_mangle]
pub extern "C" fn lazyframe_join(
    left_ptr: *mut LazyFrame,
    right_ptr: *mut LazyFrame,
    left_on_ptrs: *const *const c_char,
    n_left_on: usize,
    right_on_ptrs: *const *const c_char,
    n_right_on: usize,
    how: i32,
) -> *mut LazyFrame {
    if left_ptr.is_null() || right_ptr.is_null() {
        return ptr::null_mut();
    }
    let left = unsafe { (*left_ptr).clone() };
    let right = unsafe { (*right_ptr).clone() };
    if how == CompatJoinKind::Cross as i32 {
        return Box::into_raw(Box::new(left.cross_join(right, None)));
    }
    let join_type = match how {
        x if x == CompatJoinKind::Inner as i32 => {
            polars::prelude::JoinType::Inner
        }
        x if x == CompatJoinKind::Left as i32 => {
            polars::prelude::JoinType::Left
        }
        x if x == CompatJoinKind::Outer as i32 => {
            polars::prelude::JoinType::Full
        }
        x if x == CompatJoinKind::Semi as i32 => {
            polars::prelude::JoinType::Semi
        }
        x if x == CompatJoinKind::Anti as i32 => {
            polars::prelude::JoinType::Anti
        }
        _ => return ptr::null_mut(),
    };
    let left_on = match unsafe { collect_c_strings(left_on_ptrs, n_left_on) } {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    let right_on = match unsafe { collect_c_strings(right_on_ptrs, n_right_on) }
    {
        Some(v) => v,
        None => return ptr::null_mut(),
    };
    if left_on.is_empty() || right_on.is_empty() {
        return ptr::null_mut();
    }
    let left_exprs: Vec<Expr> = left_on.iter().map(|n| col(n)).collect();
    let right_exprs: Vec<Expr> = right_on.iter().map(|n| col(n)).collect();
    let args = polars::prelude::JoinArgs::new(join_type);
    Box::into_raw(Box::new(left.join(right, left_exprs, right_exprs, args)))
}

// ===== Phase A9: expr cast =====
//
// Takes a CompatDType *by value* (same struct used on the output side
// of `series_dtype`).  Unsupported tags (List/Array/Struct/Decimal/...)
// return null so the Racket side can raise rather than panic.

#[no_mangle]
pub extern "C" fn expr_cast(e: *mut Expr, target: CompatDType) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let dt = match polars_dtype_from_compat(&target) {
        Some(d) => d,
        None => return ptr::null_mut(),
    };
    let e_ref = unsafe { (*e).clone() };
    Box::into_raw(Box::new(e_ref.cast(dt)))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ptr;

    #[test]
    fn test_series_name_non_null() {
        let series = series_make();
        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "example");

        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_name_null() {
        let name_ptr = series_name(ptr::null_mut());
        assert!(name_ptr.is_null());
    }

    #[test]
    fn free_non_null_series() {
        let series = series_make();
        assert!(!series.is_null());
        series_drop(series);
    }

    #[test]
    fn free_empty_series() {
        let series = series_empty();
        assert!(!series.is_null());
        series_drop(series);
    }

    #[test]
    fn free_null_series() {
        let series: *mut Series = ptr::null_mut();
        series_drop(series);
    }

    #[test]
    fn test_empty_series_name() {
        let series = series_empty();
        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_rename_series_non_null() {
        let series = series_make();

        let new_name = CString::new("new_name").unwrap();
        let new_name_ptr = new_name.as_ptr();

        series_rename(series, new_name_ptr);

        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "new_name");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_rename_series_with_empty_string() {
        let series = series_make();

        let new_name = CString::new("").unwrap();
        let new_name_ptr = new_name.as_ptr();

        series_rename(series, new_name_ptr);

        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_rename_series_null_series_pointer() {
        let new_name = CString::new("new_name").unwrap();
        let new_name_ptr = new_name.as_ptr();

        series_rename(ptr::null_mut(), new_name_ptr);
    }

    #[test]
    fn test_rename_series_null_new_name_pointer() {
        let series = series_make();

        series_rename(series, ptr::null());

        // Ensure the original name remains unchanged
        let name_ptr = series_name(series);
        assert!(!name_ptr.is_null());

        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let name = c_str.to_str().unwrap();
        assert_eq!(name, "example");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_dtype_non_null() {
        let series = series_make();
        let dtype = series_dtype(series);
        assert_eq!(dtype.tag, CompatDTypeTag::Int32 as i32);
        assert_eq!(dtype.time_unit, CompatTimeUnit::None as i32);
        assert_eq!(dtype.flags, 0);
        assert_eq!(dtype.array_width, 0);

        series_drop(series);
    }

    #[test]
    fn test_series_dtype_null() {
        let dtype = series_dtype(ptr::null_mut());
        assert_eq!(dtype.tag, CompatDTypeTag::Unknown as i32);
        assert_eq!(dtype.time_unit, CompatTimeUnit::None as i32);
    }

    #[test]
    fn free_non_null_dataframe() {
        let df = dataframe_make();
        assert!(!df.is_null());
        dataframe_drop(df);
    }

    #[test]
    fn free_empty_dataframe() {
        let df = dataframe_empty();
        assert!(!df.is_null());
        dataframe_drop(df);
    }

    #[test]
    fn free_null_dataframe() {
        let df: *mut DataFrame = ptr::null_mut();
        dataframe_drop(df);
    }

    #[test]
    fn get_shape_of_non_null_dataframe() {
        let df = dataframe_make();
        let shape = dataframe_shape(df);
        assert_eq!(shape.rows, 0);
        assert_eq!(shape.cols, 0);
        dataframe_drop(df);
    }

    #[test]
    fn get_shape_of_empty_dataframe() {
        let df = dataframe_empty();
        let shape = dataframe_shape(df);
        assert_eq!(shape.rows, 0);
        assert_eq!(shape.cols, 0);
        dataframe_drop(df);
    }

    #[test]
    fn get_shape_of_null_dataframe() {
        let df: *mut DataFrame = ptr::null_mut();
        let shape = dataframe_shape(df);
        assert_eq!(shape.rows, 0);
        assert_eq!(shape.cols, 0);
    }

    #[test]
    fn test_series_len_non_null() {
        let series = series_make();
        let len = series_len(series);
        assert_eq!(len, 4);
        series_drop(series);
    }

    #[test]
    fn test_series_len_null() {
        let len = series_len(ptr::null_mut());
        assert_eq!(len, 0);
    }

    #[test]
    fn test_series_len_empty_series() {
        let series = series_empty();
        let len = series_len(series);
        assert_eq!(len, 0);
        series_drop(series);
    }

    #[test]
    fn test_series_null_count_non_null() {
        let series = series_make();
        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);
        series_drop(series);
    }

    #[test]
    fn test_series_null_count_null() {
        let null_count = series_null_count(ptr::null_mut());
        assert_eq!(null_count, 0);
    }

    #[test]
    fn test_series_null_count_empty_series() {
        let series = series_empty();
        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);
        series_drop(series);
    }

    #[test]
    fn test_series_new_i32_valid() {
        let data = vec![1, 2, 3, 4];
        let data_ptr = data.as_ptr();

        let name = CString::new("i32_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_i32(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 4);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "i32_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_new_i32_null_name() {
        let data = vec![1, 2, 3, 4];
        let data_ptr = data.as_ptr();

        let series = series_new_i32(ptr::null(), data_ptr, data.len());
        assert!(series.is_null());
    }

    #[test]
    fn test_series_new_i32_null_data() {
        let name = CString::new("i32_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_i32(name_ptr, ptr::null(), 4);
        assert!(series.is_null());
    }

    #[test]
    fn test_series_new_i32_empty_data() {
        let data: Vec<i32> = Vec::new();
        let data_ptr = data.as_ptr();

        let name = CString::new("i32_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_i32(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 0);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "i32_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_string_drop_non_null() {
        let s = CString::new("hello").unwrap();
        let s_ptr = s.into_raw();

        string_drop(s_ptr);
    }

    #[test]
    fn test_string_drop_null() {
        string_drop(ptr::null_mut());
        // Should not do anything, hence no assertion or panic
    }

    #[test]
    fn test_series_new_f64_valid() {
        let data = vec![1.1, 2.2, 3.3, 4.4];
        let data_ptr = data.as_ptr();

        let name = CString::new("f64_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_f64(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 4);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "f64_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_new_str_valid() {
        let data = vec![
            CString::new("one").unwrap(),
            CString::new("two").unwrap(),
            CString::new("three").unwrap(),
        ];
        let data_ptrs: Vec<*const c_char> =
            data.iter().map(|s| s.as_ptr()).collect();
        let data_ptr = data_ptrs.as_ptr();

        let name = CString::new("str_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_str(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 3);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "str_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_new_str_null_name() {
        let data = vec![
            CString::new("one").unwrap(),
            CString::new("two").unwrap(),
            CString::new("three").unwrap(),
        ];
        let data_ptrs: Vec<*const c_char> =
            data.iter().map(|s| s.as_ptr()).collect();
        let data_ptr = data_ptrs.as_ptr();

        let series = series_new_str(ptr::null(), data_ptr, data.len());
        assert!(!series.is_null());
    }

    #[test]
    fn test_series_new_str_null_data() {
        let name = CString::new("str_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_str(name_ptr, ptr::null(), 3);
        assert!(series.is_null());
    }

    #[test]
    fn test_series_new_str_empty_data() {
        let data: Vec<*const c_char> = Vec::new();
        let data_ptr = data.as_ptr();

        let name = CString::new("str_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_str(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 0);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "str_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_new_ymdhms_valid() {
        let data = vec![
            YMDHMS {
                year: 2021,
                month: 5,
                day: 20,
                hour: 10,
                minute: 30,
                second: 45,
            },
            YMDHMS {
                year: 2022,
                month: 6,
                day: 21,
                hour: 11,
                minute: 31,
                second: 46,
            },
        ];
        let data_ptr = data.as_ptr();

        let name = CString::new("ymdhms_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_ymdhms(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 2);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "ymdhms_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }

    #[test]
    fn test_series_new_ymdhms_null_name() {
        let data = vec![
            YMDHMS {
                year: 2021,
                month: 5,
                day: 20,
                hour: 10,
                minute: 30,
                second: 45,
            },
            YMDHMS {
                year: 2022,
                month: 6,
                day: 21,
                hour: 11,
                minute: 31,
                second: 46,
            },
        ];
        let data_ptr = data.as_ptr();

        let series = series_new_ymdhms(ptr::null(), data_ptr, data.len());
        assert!(!series.is_null());
    }

    #[test]
    fn test_series_new_ymdhms_null_data() {
        let name = CString::new("ymdhms_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_ymdhms(name_ptr, ptr::null(), 2);
        assert!(series.is_null());
    }

    #[test]
    fn test_series_new_ymdhms_empty_data() {
        let data: Vec<YMDHMS> = Vec::new();
        let data_ptr = data.as_ptr();

        let name = CString::new("ymdhms_series").unwrap();
        let name_ptr = name.as_ptr();

        let series = series_new_ymdhms(name_ptr, data_ptr, data.len());
        assert!(!series.is_null());

        let len = series_len(series);
        assert_eq!(len, 0);

        let null_count = series_null_count(series);
        assert_eq!(null_count, 0);

        let name_ptr = series_name(series);
        let c_str = unsafe { CStr::from_ptr(name_ptr) };
        let series_name = c_str.to_str().unwrap();
        assert_eq!(series_name, "ymdhms_series");

        // Free the CString allocated by series_name
        unsafe { drop(CString::from_raw(name_ptr as *mut c_char)) };

        series_drop(series);
    }
}
