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

// ----- cumulative + shift / diff -----

expr_unop_u8!(expr_cum_sum, |e, rev| e.cum_sum(rev != 0));
expr_unop_u8!(expr_cum_prod, |e, rev| e.cum_prod(rev != 0));
expr_unop_u8!(expr_cum_min, |e, rev| e.cum_min(rev != 0));
expr_unop_u8!(expr_cum_max, |e, rev| e.cum_max(rev != 0));
expr_unop_u8!(expr_cum_count, |e, rev| e.cum_count(rev != 0));

#[no_mangle]
pub extern "C" fn expr_shift(e: *const Expr, n: i64) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.shift(lit(n))))
}

#[no_mangle]
pub extern "C" fn expr_shift_and_fill(
    e: *const Expr,
    n: i64,
    fill_value: *const Expr,
) -> *mut Expr {
    if e.is_null() || fill_value.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let fv = unsafe { (*fill_value).clone() };
    Box::into_raw(Box::new(ee.shift_and_fill(lit(n), fv)))
}

/// `diff` with a `null_behavior` selector: 0 = ignore (default), 1 = drop.
#[no_mangle]
pub extern "C" fn expr_diff(e: *const Expr, n: i64, null_behavior: u8) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let nb = if null_behavior == 1 {
        polars::series::ops::NullBehavior::Drop
    } else {
        polars::series::ops::NullBehavior::Ignore
    };
    Box::into_raw(Box::new(ee.diff(n, nb)))
}

// ----- sorting / selection helpers -----

expr_unop!(expr_reverse, |e| e.reverse());
expr_binop!(expr_filter, |a, b| a.filter(b));
expr_binop!(expr_gather, |a, b| a.gather(b));

/// sort_by parallel `by` exprs + `descending` flags (length `n`).
#[no_mangle]
pub extern "C" fn expr_sort_by(
    e: *const Expr,
    by: *const *const Expr,
    descending: *const u8,
    n: usize,
) -> *mut Expr {
    if e.is_null() || by.is_null() || descending.is_null() || n == 0 {
        return ptr::null_mut();
    }
    let by = unsafe { std::slice::from_raw_parts(by, n) };
    let desc = unsafe { std::slice::from_raw_parts(descending, n) };
    if by.iter().any(|p| p.is_null()) {
        return ptr::null_mut();
    }
    let by_vec: Vec<Expr> = by.iter().map(|p| unsafe { (**p).clone() }).collect();
    let desc_vec: Vec<bool> = desc.iter().map(|b| *b != 0).collect();
    let ee = unsafe { (*e).clone() };
    let opts = SortMultipleOptions::default().with_order_descending_multi(desc_vec);
    Box::into_raw(Box::new(ee.sort_by(by_vec, opts)))
}

/// rank with `method` (0 average, 1 min, 2 max, 3 dense, 4 ordinal),
/// `descending`, and an optional `seed`.
#[no_mangle]
pub extern "C" fn expr_rank(
    e: *const Expr,
    method: u8,
    descending: u8,
    has_seed: u8,
    seed: u64,
) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let m = match method {
        1 => RankMethod::Min,
        2 => RankMethod::Max,
        3 => RankMethod::Dense,
        4 => RankMethod::Ordinal,
        _ => RankMethod::Average,
    };
    let ee = unsafe { (*e).clone() };
    let opts = RankOptions {
        method: m,
        descending: descending != 0,
    };
    let s = if has_seed != 0 { Some(seed) } else { None };
    Box::into_raw(Box::new(ee.rank(opts, s)))
}

#[no_mangle]
pub extern "C" fn expr_head(e: *const Expr, has_len: u8, len: usize) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let n = if has_len != 0 { Some(len) } else { None };
    Box::into_raw(Box::new(ee.head(n)))
}

#[no_mangle]
pub extern "C" fn expr_tail(e: *const Expr, has_len: u8, len: usize) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    let n = if has_len != 0 { Some(len) } else { None };
    Box::into_raw(Box::new(ee.tail(n)))
}

#[no_mangle]
pub extern "C" fn expr_slice(e: *const Expr, offset: i64, length: i64) -> *mut Expr {
    if e.is_null() {
        return ptr::null_mut();
    }
    let ee = unsafe { (*e).clone() };
    Box::into_raw(Box::new(ee.slice(lit(offset), lit(length))))
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

    // ===== R1: test helpers + ABI round trips =====

    /// Shared helpers reused by later test sub-modules. Centralizes the
    /// CString-lifetime and series-builder patterns the early tests
    /// open-code so new tests don't have to repeat them.
    mod test_util {
        use super::*;

        /// Build an owning `CString` from a Rust `&str`. The caller holds
        /// the `CString` for as long as the FFI call needs the pointer.
        pub(super) fn cstr(s: &str) -> CString {
            CString::new(s).expect("test cstring must not contain a nul byte")
        }

        /// Materialize a `*const c_char` that an FFI extern returned into
        /// an owned `String`, freeing the underlying CString.
        pub(super) fn take_cstring(p: *const c_char) -> String {
            assert!(!p.is_null(), "expected a non-null CString pointer");
            let s = unsafe { CStr::from_ptr(p) }
                .to_str()
                .expect("FFI string must be valid UTF-8")
                .to_owned();
            unsafe { drop(CString::from_raw(p as *mut c_char)) };
            s
        }

        pub(super) fn make_i32(name: &str, values: &[i32]) -> *mut Series {
            let n = cstr(name);
            let s = series_new_i32(n.as_ptr(), values.as_ptr(), values.len());
            assert!(!s.is_null(), "series_new_i32 returned null for {:?}", name);
            s
        }

        pub(super) fn make_f64(name: &str, values: &[f64]) -> *mut Series {
            let n = cstr(name);
            let s = series_new_f64(n.as_ptr(), values.as_ptr(), values.len());
            assert!(!s.is_null());
            s
        }

        pub(super) fn make_bool(name: &str, values: &[u8]) -> *mut Series {
            let n = cstr(name);
            let s = series_new_bool(n.as_ptr(), values.as_ptr(), values.len());
            assert!(!s.is_null());
            s
        }

        pub(super) fn make_str(name: &str, values: &[&str]) -> *mut Series {
            // series_new_str takes an array of `*const c_char`; keep the
            // CStrings alive for the duration of the call.
            let owned: Vec<CString> = values.iter().map(|v| cstr(v)).collect();
            let ptrs: Vec<*const c_char> =
                owned.iter().map(|c| c.as_ptr()).collect();
            let n = cstr(name);
            let s = series_new_str(n.as_ptr(), ptrs.as_ptr(), ptrs.len());
            assert!(!s.is_null());
            s
        }

        pub(super) fn make_i64(name: &str, values: &[i64]) -> *mut Series {
            let n = cstr(name);
            let s = series_new_i64(n.as_ptr(), values.as_ptr(), values.len());
            assert!(!s.is_null());
            s
        }

        /// Build a null-aware primitive series from `Option<T>` values
        /// the same way `series_new_opt_*` is used from Racket.
        pub(super) fn make_opt_i32(
            name: &str,
            values: &[Option<i32>],
        ) -> *mut Series {
            let data: Vec<i32> =
                values.iter().map(|o| o.unwrap_or(0)).collect();
            let valid: Vec<u8> = values
                .iter()
                .map(|o| if o.is_some() { 1 } else { 0 })
                .collect();
            let n = cstr(name);
            let s = series_new_opt_i32(
                n.as_ptr(),
                data.as_ptr(),
                valid.as_ptr(),
                data.len(),
            );
            assert!(!s.is_null());
            s
        }

        /// Build a DataFrame from a slice of already-owned Series
        /// pointers. The caller still owns each input Series and is
        /// responsible for dropping them — `dataframe_new` clones them.
        pub(super) fn make_df(columns: &[*mut Series]) -> *mut DataFrame {
            let ptrs: Vec<*const Series> =
                columns.iter().map(|p| *p as *const Series).collect();
            let df = dataframe_new(ptrs.as_ptr(), ptrs.len());
            assert!(!df.is_null(), "dataframe_new returned null");
            df
        }

        /// Read every column name back through the FFI.
        pub(super) fn read_column_names(df: *mut DataFrame) -> Vec<String> {
            (0..dataframe_width(df))
                .map(|i| take_cstring(dataframe_column_name(df, i)))
                .collect()
        }

        /// Pull a string column out by name and materialize it as a
        /// `Vec<String>`. Each element is freed via `take_cstring`.
        pub(super) fn read_str_col(
            df: *mut DataFrame,
            name: &str,
        ) -> Vec<String> {
            let n = cstr(name);
            let s = dataframe_column(df, n.as_ptr());
            assert!(
                !s.is_null(),
                "dataframe_column({:?}) returned null",
                name,
            );
            let out: Vec<String> = (0..series_len(s))
                .map(|i| {
                    let p = series_ref_str(s, i);
                    assert!(!p.is_null(), "unexpected null at {}/{}", name, i);
                    take_cstring(p)
                })
                .collect();
            series_drop(s);
            out
        }

        /// Pull an i64 column out by name and materialize it as a Vec.
        /// CSV / JSON-Lines readers infer integer columns as i64, so
        /// round-trip tests need to read with this variant.
        pub(super) fn read_i64_col(
            df: *mut DataFrame,
            name: &str,
        ) -> Vec<i64> {
            let n = cstr(name);
            let s = dataframe_column(df, n.as_ptr());
            assert!(
                !s.is_null(),
                "dataframe_column({:?}) returned null",
                name,
            );
            let out: Vec<i64> = (0..series_len(s))
                .map(|i| {
                    let v = series_ref_i64(s, i);
                    assert_eq!(v.valid, 1, "unexpected null at {}/{}", name, i);
                    v.value
                })
                .collect();
            series_drop(s);
            out
        }

        /// Pull an i32 column out by name and materialize it as a Vec.
        pub(super) fn read_i32_col(
            df: *mut DataFrame,
            name: &str,
        ) -> Vec<i32> {
            let n = cstr(name);
            let s = dataframe_column(df, n.as_ptr());
            assert!(
                !s.is_null(),
                "dataframe_column({:?}) returned null",
                name,
            );
            let out: Vec<i32> = (0..series_len(s))
                .map(|i| {
                    let v = series_ref_i32(s, i);
                    assert_eq!(v.valid, 1, "unexpected null at {}/{}", name, i);
                    v.value
                })
                .collect();
            series_drop(s);
            out
        }

        pub(super) fn make_opt_f64(
            name: &str,
            values: &[Option<f64>],
        ) -> *mut Series {
            let data: Vec<f64> =
                values.iter().map(|o| o.unwrap_or(0.0)).collect();
            let valid: Vec<u8> = values
                .iter()
                .map(|o| if o.is_some() { 1 } else { 0 })
                .collect();
            let n = cstr(name);
            let s = series_new_opt_f64(
                n.as_ptr(),
                data.as_ptr(),
                valid.as_ptr(),
                data.len(),
            );
            assert!(!s.is_null());
            s
        }

        /// Assert that `series_dtype` reports the given tag and time-unit.
        pub(super) fn assert_dtype(
            series: *mut Series,
            tag: CompatDTypeTag,
            time_unit: CompatTimeUnit,
        ) {
            let dt = series_dtype(series);
            assert_eq!(dt.tag, tag as i32, "dtype tag mismatch");
            assert_eq!(
                dt.time_unit, time_unit as i32,
                "dtype time_unit mismatch",
            );
        }
    }

    /// Direct unit tests for the internal ABI conversion helpers
    /// (`compat_dtype_from_polars`, `polars_dtype_from_compat`,
    /// `ymdhms_to_naive_datetime`). These aren't `extern "C"`, so the
    /// only thing that currently exercises them is the dylib being
    /// loaded by Racket.
    mod abi {
        use super::*;

        fn round_trip_simple(tag: CompatDTypeTag, expect: DataType) {
            let c = CompatDType {
                tag: tag as i32,
                time_unit: CompatTimeUnit::None as i32,
                flags: 0,
                array_width: 0,
            };
            let dt = polars_dtype_from_compat(&c)
                .expect("simple dtype must lift");
            assert_eq!(dt, expect);
            let back = compat_dtype_from_polars(&dt);
            assert_eq!(back.tag, c.tag);
            assert_eq!(back.time_unit, CompatTimeUnit::None as i32);
        }

        #[test]
        fn round_trip_boolean() {
            round_trip_simple(CompatDTypeTag::Boolean, DataType::Boolean);
        }
        #[test]
        fn round_trip_uint8() {
            round_trip_simple(CompatDTypeTag::UInt8, DataType::UInt8);
        }
        #[test]
        fn round_trip_uint16() {
            round_trip_simple(CompatDTypeTag::UInt16, DataType::UInt16);
        }
        #[test]
        fn round_trip_uint32() {
            round_trip_simple(CompatDTypeTag::UInt32, DataType::UInt32);
        }
        #[test]
        fn round_trip_uint64() {
            round_trip_simple(CompatDTypeTag::UInt64, DataType::UInt64);
        }
        #[test]
        fn round_trip_int8() {
            round_trip_simple(CompatDTypeTag::Int8, DataType::Int8);
        }
        #[test]
        fn round_trip_int16() {
            round_trip_simple(CompatDTypeTag::Int16, DataType::Int16);
        }
        #[test]
        fn round_trip_int32() {
            round_trip_simple(CompatDTypeTag::Int32, DataType::Int32);
        }
        #[test]
        fn round_trip_int64() {
            round_trip_simple(CompatDTypeTag::Int64, DataType::Int64);
        }
        #[test]
        fn round_trip_float32() {
            round_trip_simple(CompatDTypeTag::Float32, DataType::Float32);
        }
        #[test]
        fn round_trip_float64() {
            round_trip_simple(CompatDTypeTag::Float64, DataType::Float64);
        }
        #[test]
        fn round_trip_string() {
            round_trip_simple(CompatDTypeTag::String, DataType::String);
        }
        #[test]
        fn round_trip_binary() {
            round_trip_simple(CompatDTypeTag::Binary, DataType::Binary);
        }
        #[test]
        fn round_trip_date() {
            round_trip_simple(CompatDTypeTag::Date, DataType::Date);
        }
        #[test]
        fn round_trip_time() {
            round_trip_simple(CompatDTypeTag::Time, DataType::Time);
        }
        #[test]
        fn round_trip_null() {
            round_trip_simple(CompatDTypeTag::Null, DataType::Null);
        }

        #[test]
        fn round_trip_datetime_each_unit() {
            for tu in [
                CompatTimeUnit::Nanoseconds,
                CompatTimeUnit::Microseconds,
                CompatTimeUnit::Milliseconds,
            ] {
                let c = CompatDType {
                    tag: CompatDTypeTag::Datetime as i32,
                    time_unit: tu as i32,
                    flags: 0,
                    array_width: 0,
                };
                let dt = polars_dtype_from_compat(&c)
                    .expect("datetime must lift");
                match dt {
                    DataType::Datetime(u, None) => {
                        assert_eq!(
                            compat_time_unit_from_polars(&u) as i32,
                            tu as i32,
                            "time-unit round-trip failed",
                        );
                    }
                    other => panic!("expected Datetime, got {:?}", other),
                }
                let back = compat_dtype_from_polars(&dt);
                assert_eq!(back.tag, CompatDTypeTag::Datetime as i32);
                assert_eq!(back.time_unit, tu as i32);
            }
        }

        #[test]
        fn round_trip_duration_each_unit() {
            for tu in [
                CompatTimeUnit::Nanoseconds,
                CompatTimeUnit::Microseconds,
                CompatTimeUnit::Milliseconds,
            ] {
                let c = CompatDType {
                    tag: CompatDTypeTag::Duration as i32,
                    time_unit: tu as i32,
                    flags: 0,
                    array_width: 0,
                };
                let dt = polars_dtype_from_compat(&c)
                    .expect("duration must lift");
                match dt {
                    DataType::Duration(u) => {
                        assert_eq!(
                            compat_time_unit_from_polars(&u) as i32,
                            tu as i32,
                            "time-unit round-trip failed",
                        );
                    }
                    other => panic!("expected Duration, got {:?}", other),
                }
                let back = compat_dtype_from_polars(&dt);
                assert_eq!(back.tag, CompatDTypeTag::Duration as i32);
                assert_eq!(back.time_unit, tu as i32);
            }
        }

        /// Tags accepted on *output* but not as input — the helper must
        /// return `None` rather than panic.
        #[test]
        fn rejected_input_tags_return_none() {
            for tag in [
                CompatDTypeTag::Unknown,
                CompatDTypeTag::BinaryOffset,
                CompatDTypeTag::List,
                CompatDTypeTag::Array,
                CompatDTypeTag::Struct,
                CompatDTypeTag::Categorical,
                CompatDTypeTag::Enum,
                CompatDTypeTag::Decimal,
                CompatDTypeTag::Object,
            ] {
                let c = CompatDType {
                    tag: tag as i32,
                    time_unit: CompatTimeUnit::None as i32,
                    flags: 0,
                    array_width: 0,
                };
                assert!(
                    polars_dtype_from_compat(&c).is_none(),
                    "tag {:?} unexpectedly lifted",
                    tag,
                );
            }
        }

        #[test]
        fn ymdhms_round_trip_to_naive_datetime() {
            let y = YMDHMS {
                year: 2024,
                month: 7,
                day: 15,
                hour: 9,
                minute: 30,
                second: 45,
            };
            let ndt =
                ymdhms_to_naive_datetime(&y).expect("valid YMDHMS converts");
            assert_eq!(ndt.date().year(), 2024);
            assert_eq!(ndt.date().month(), 7);
            assert_eq!(ndt.date().day(), 15);
            assert_eq!(ndt.time().hour(), 9);
            assert_eq!(ndt.time().minute(), 30);
            assert_eq!(ndt.time().second(), 45);
        }

        #[test]
        fn ymdhms_invalid_returns_none() {
            // February 30th doesn't exist — the helper must reject it.
            let y = YMDHMS {
                year: 2024,
                month: 2,
                day: 30,
                hour: 0,
                minute: 0,
                second: 0,
            };
            assert!(ymdhms_to_naive_datetime(&y).is_none());
        }
    }

    /// Smoke tests confirming the `test_util` helpers themselves behave
    /// (so a failure there can't silently mask later batch tests).
    mod test_util_smoke {
        use super::*;
        use super::test_util::*;

        #[test]
        fn make_i32_builds_named_series() {
            let s = make_i32("xs", &[1, 2, 3, 4]);
            let n = take_cstring(series_name(s));
            assert_eq!(n, "xs");
            assert_eq!(series_len(s), 4);
            assert_dtype(s, CompatDTypeTag::Int32, CompatTimeUnit::None);
            series_drop(s);
        }

        #[test]
        fn make_f64_builds_named_series() {
            let s = make_f64("ys", &[1.5, 2.5]);
            assert_eq!(series_len(s), 2);
            assert_dtype(s, CompatDTypeTag::Float64, CompatTimeUnit::None);
            series_drop(s);
        }

        #[test]
        fn make_bool_builds_named_series() {
            let s = make_bool("flags", &[1u8, 0, 1]);
            assert_eq!(series_len(s), 3);
            assert_dtype(s, CompatDTypeTag::Boolean, CompatTimeUnit::None);
            series_drop(s);
        }

        #[test]
        fn make_str_builds_named_series() {
            let s = make_str("words", &["a", "bb", "ccc"]);
            assert_eq!(series_len(s), 3);
            assert_dtype(s, CompatDTypeTag::String, CompatTimeUnit::None);
            series_drop(s);
        }
    }

    // ===== R2: Series constructors + value access =====

    /// Round out the `series_new_*` family: every width gets a happy
    /// path (length + dtype tag) and the null-name / null-data refusal
    /// paths the i32 tests already establish are repeated for one
    /// representative per family to guard the macro expansion.
    mod series_ctors {
        use super::*;
        use super::test_util::*;

        macro_rules! ctor_happy_path {
            ($name:ident, $build:expr, $tag:ident) => {
                #[test]
                fn $name() {
                    let s = $build;
                    assert_eq!(series_len(s), 4);
                    assert_dtype(
                        s,
                        CompatDTypeTag::$tag,
                        CompatTimeUnit::None,
                    );
                    series_drop(s);
                }
            };
        }

        ctor_happy_path!(ctor_i8, {
            let n = cstr("xs");
            let data: [i8; 4] = [-1, 0, 1, 2];
            series_new_i8(n.as_ptr(), data.as_ptr(), data.len())
        }, Int8);
        ctor_happy_path!(ctor_i16, {
            let n = cstr("xs");
            let data: [i16; 4] = [-1, 0, 1, 2];
            series_new_i16(n.as_ptr(), data.as_ptr(), data.len())
        }, Int16);
        ctor_happy_path!(ctor_i64, make_i64("xs", &[-1, 0, 1, 2]), Int64);
        ctor_happy_path!(ctor_u8, {
            let n = cstr("xs");
            let data: [u8; 4] = [0, 1, 2, 3];
            series_new_u8(n.as_ptr(), data.as_ptr(), data.len())
        }, UInt8);
        ctor_happy_path!(ctor_u16, {
            let n = cstr("xs");
            let data: [u16; 4] = [0, 1, 2, 3];
            series_new_u16(n.as_ptr(), data.as_ptr(), data.len())
        }, UInt16);
        ctor_happy_path!(ctor_u32, {
            let n = cstr("xs");
            let data: [u32; 4] = [0, 1, 2, 3];
            series_new_u32(n.as_ptr(), data.as_ptr(), data.len())
        }, UInt32);
        ctor_happy_path!(ctor_u64, {
            let n = cstr("xs");
            let data: [u64; 4] = [0, 1, 2, 3];
            series_new_u64(n.as_ptr(), data.as_ptr(), data.len())
        }, UInt64);
        ctor_happy_path!(ctor_f32, {
            let n = cstr("xs");
            let data: [f32; 4] = [0.0, 1.5, -2.5, 3.0];
            series_new_f32(n.as_ptr(), data.as_ptr(), data.len())
        }, Float32);
        ctor_happy_path!(ctor_bool, make_bool("flags", &[1, 0, 1, 0]), Boolean);

        #[test]
        fn ctor_i64_null_name_returns_null() {
            let data: [i64; 1] = [42];
            let s = series_new_i64(ptr::null(), data.as_ptr(), data.len());
            assert!(s.is_null(), "null name must produce null Series");
        }

        #[test]
        fn ctor_u32_null_data_returns_null() {
            let n = cstr("xs");
            let s = series_new_u32(n.as_ptr(), ptr::null(), 4);
            assert!(s.is_null(), "null data + nonzero length must reject");
        }

        #[test]
        fn ctor_bool_null_name_returns_null() {
            let data: [u8; 1] = [1];
            let s = series_new_bool(ptr::null(), data.as_ptr(), data.len());
            assert!(s.is_null());
        }

        #[test]
        fn ctor_bool_empty_ok() {
            // Empty bool series is allowed: data may be null when length=0.
            let n = cstr("flags");
            let s = series_new_bool(n.as_ptr(), ptr::null(), 0);
            assert!(!s.is_null());
            assert_eq!(series_len(s), 0);
            series_drop(s);
        }

        #[test]
        fn ctor_ymdhms_happy_path() {
            let n = cstr("ts");
            let data = [
                YMDHMS { year: 2024, month: 1, day: 2,
                         hour: 3, minute: 4, second: 5 },
                YMDHMS { year: 2025, month: 6, day: 7,
                         hour: 8, minute: 9, second: 10 },
            ];
            let s = series_new_ymdhms(n.as_ptr(), data.as_ptr(), data.len());
            assert!(!s.is_null());
            assert_eq!(series_len(s), 2);
            assert_dtype(s, CompatDTypeTag::Datetime,
                         CompatTimeUnit::Milliseconds);
            series_drop(s);
        }
    }

    /// Null-aware (`series_new_opt_*`) constructors: mixed valid/invalid
    /// inputs survive the round trip via `series_ref_*`.
    mod series_opt_ctors {
        use super::*;
        use super::test_util::*;

        #[test]
        fn opt_i32_mixed_valid_round_trips() {
            let s = make_opt_i32(
                "xs",
                &[Some(10), None, Some(30), None],
            );
            assert_eq!(series_len(s), 4);
            assert_eq!(series_null_count(s), 2);
            assert_eq!(series_ref_i32(s, 0), CompatOptI32 { valid: 1, value: 10 });
            assert_eq!(series_ref_i32(s, 1), CompatOptI32 { valid: 0, value: 0 });
            assert_eq!(series_ref_i32(s, 2), CompatOptI32 { valid: 1, value: 30 });
            assert_eq!(series_ref_i32(s, 3), CompatOptI32 { valid: 0, value: 0 });
            series_drop(s);
        }

        #[test]
        fn opt_f64_mixed_valid_round_trips() {
            let s = make_opt_f64("ys", &[Some(1.5), None, Some(-2.25)]);
            assert_eq!(series_null_count(s), 1);
            let v0 = series_ref_f64(s, 0);
            assert_eq!(v0.valid, 1);
            assert_eq!(v0.value, 1.5);
            let v1 = series_ref_f64(s, 1);
            assert_eq!(v1.valid, 0);
            let v2 = series_ref_f64(s, 2);
            assert_eq!(v2.valid, 1);
            assert_eq!(v2.value, -2.25);
            series_drop(s);
        }

        #[test]
        fn opt_str_mixed_valid_round_trips() {
            // series_new_opt_str: parallel data + valid arrays. NULL
            // entries in the data slot are tolerated when valid=0.
            let owned = [cstr("hi"), cstr("there")];
            let data = [owned[0].as_ptr(), ptr::null(), owned[1].as_ptr()];
            let valid = [1u8, 0, 1];
            let n = cstr("ws");
            let s = series_new_opt_str(
                n.as_ptr(),
                data.as_ptr(),
                valid.as_ptr(),
                data.len(),
            );
            assert!(!s.is_null());
            assert_eq!(series_null_count(s), 1);
            assert_eq!(take_cstring(series_ref_str(s, 0)), "hi");
            assert!(series_ref_str(s, 1).is_null());
            assert_eq!(take_cstring(series_ref_str(s, 2)), "there");
            series_drop(s);
        }

        #[test]
        fn opt_bool_mixed_valid_round_trips() {
            let n = cstr("flags");
            let data: [u8; 3] = [1, 0, 1];
            let valid: [u8; 3] = [1, 0, 1];
            let s = series_new_opt_bool(
                n.as_ptr(),
                data.as_ptr(),
                valid.as_ptr(),
                data.len(),
            );
            assert!(!s.is_null());
            assert_eq!(series_null_count(s), 1);
            assert_eq!(series_ref_bool(s, 0).valid, 1);
            assert_eq!(series_ref_bool(s, 0).value, 1);
            assert_eq!(series_ref_bool(s, 1).valid, 0);
            assert_eq!(series_ref_bool(s, 2).value, 1);
            series_drop(s);
        }

        #[test]
        fn opt_i32_empty_ok() {
            let n = cstr("xs");
            let s = series_new_opt_i32(n.as_ptr(), ptr::null(), ptr::null(), 0);
            assert!(!s.is_null());
            assert_eq!(series_len(s), 0);
            series_drop(s);
        }

        #[test]
        fn opt_i64_null_name_returns_null() {
            let data: [i64; 1] = [1];
            let valid: [u8; 1] = [1];
            let s = series_new_opt_i64(
                ptr::null(),
                data.as_ptr(),
                valid.as_ptr(),
                1,
            );
            assert!(s.is_null());
        }

        #[test]
        fn opt_ymdhms_mixed_valid_round_trips() {
            let n = cstr("ts");
            let data = [
                YMDHMS { year: 2024, month: 1, day: 2,
                         hour: 3, minute: 4, second: 5 },
                YMDHMS { year: 0, month: 0, day: 0,
                         hour: 0, minute: 0, second: 0 },
            ];
            let valid = [1u8, 0];
            let s = series_new_opt_ymdhms(
                n.as_ptr(),
                data.as_ptr(),
                valid.as_ptr(),
                data.len(),
            );
            assert!(!s.is_null());
            assert_eq!(series_null_count(s), 1);
            let v0 = series_ref_ymdhms(s, 0);
            assert_eq!(v0.valid, 1);
            assert_eq!(v0.value.year, 2024);
            assert_eq!(v0.value.month, 1);
            assert_eq!(v0.value.hour, 3);
            let v1 = series_ref_ymdhms(s, 1);
            assert_eq!(v1.valid, 0);
            series_drop(s);
        }
    }

    /// `series_ref_*` happy / null / out-of-range paths, plus the
    /// temporal accessors (Date / Time / Duration / Datetime).
    mod series_value_access {
        use super::*;
        use super::test_util::*;

        #[test]
        fn ref_i32_happy_path() {
            let s = make_i32("xs", &[10, 20, 30]);
            assert_eq!(series_ref_i32(s, 0).value, 10);
            assert_eq!(series_ref_i32(s, 2).value, 30);
            series_drop(s);
        }

        #[test]
        fn ref_i32_null_series_returns_none() {
            let v = series_ref_i32(ptr::null_mut(), 0);
            assert_eq!(v, CompatOptI32 { valid: 0, value: 0 });
        }

        #[test]
        fn ref_f64_returns_value() {
            let s = make_f64("ys", &[1.5, 2.5, 3.5]);
            assert_eq!(series_ref_f64(s, 1).value, 2.5);
            series_drop(s);
        }

        #[test]
        fn ref_str_returns_cstring_and_frees() {
            let s = make_str("ws", &["hi", "there"]);
            let p0 = series_ref_str(s, 0);
            assert!(!p0.is_null());
            assert_eq!(take_cstring(p0), "hi");
            assert_eq!(take_cstring(series_ref_str(s, 1)), "there");
            series_drop(s);
        }

        #[test]
        fn ref_str_null_series_returns_null_ptr() {
            assert!(series_ref_str(ptr::null_mut(), 0).is_null());
        }

        #[test]
        fn ref_bool_returns_value() {
            let s = make_bool("flags", &[1, 0, 1]);
            assert_eq!(series_ref_bool(s, 0).value, 1);
            assert_eq!(series_ref_bool(s, 1).value, 0);
            series_drop(s);
        }

        #[test]
        fn ref_is_null_flags_null_entries() {
            let s = make_opt_i32("xs", &[Some(1), None, Some(3)]);
            assert_eq!(series_ref_is_null(s, 0), 0);
            assert_eq!(series_ref_is_null(s, 1), 1);
            assert_eq!(series_ref_is_null(s, 2), 0);
            // out-of-range → -1
            assert_eq!(series_ref_is_null(s, 99), -1);
            // null series → -1
            assert_eq!(series_ref_is_null(ptr::null_mut(), 0), -1);
            series_drop(s);
        }

        #[test]
        fn ref_date_returns_ymd() {
            // Build an i32 series of epoch-days then cast → Date.
            let raw = make_i32("d", &[0, 1, 365]);
            let target = CompatDType {
                tag: CompatDTypeTag::Date as i32,
                time_unit: CompatTimeUnit::None as i32,
                flags: 0,
                array_width: 0,
            };
            let dates = series_cast(raw, target);
            assert!(!dates.is_null());
            assert_dtype(dates, CompatDTypeTag::Date, CompatTimeUnit::None);
            let v0 = series_ref_date(dates, 0);
            assert_eq!(v0.valid, 1);
            assert_eq!(v0.value.year, 1970);
            assert_eq!(v0.value.month, 1);
            assert_eq!(v0.value.day, 1);
            let v2 = series_ref_date(dates, 2);
            assert_eq!(v2.valid, 1);
            assert_eq!(v2.value.year, 1971);
            assert_eq!(v2.value.month, 1);
            assert_eq!(v2.value.day, 1);
            series_drop(raw);
            series_drop(dates);
        }

        #[test]
        fn ref_duration_returns_i64() {
            let raw = make_i64("d", &[0, 1_000, 60_000]);
            let target = CompatDType {
                tag: CompatDTypeTag::Duration as i32,
                time_unit: CompatTimeUnit::Milliseconds as i32,
                flags: 0,
                array_width: 0,
            };
            let durs = series_cast(raw, target);
            assert!(!durs.is_null());
            assert_dtype(durs, CompatDTypeTag::Duration,
                         CompatTimeUnit::Milliseconds);
            assert_eq!(series_ref_duration(durs, 1).value, 1_000);
            assert_eq!(series_ref_duration(durs, 2).value, 60_000);
            series_drop(raw);
            series_drop(durs);
        }

        #[test]
        fn ref_time_returns_i64() {
            // Polars Time stores nanoseconds-since-midnight as i64.
            let raw = make_i64("t", &[0, 1_000_000_000]);
            let target = CompatDType {
                tag: CompatDTypeTag::Time as i32,
                time_unit: CompatTimeUnit::None as i32,
                flags: 0,
                array_width: 0,
            };
            let times = series_cast(raw, target);
            assert!(!times.is_null());
            assert_dtype(times, CompatDTypeTag::Time, CompatTimeUnit::None);
            assert_eq!(series_ref_time(times, 0).value, 0);
            assert_eq!(series_ref_time(times, 1).value, 1_000_000_000);
            series_drop(raw);
            series_drop(times);
        }

        #[test]
        fn ref_ymdhms_returns_value() {
            let n = cstr("ts");
            let data = [YMDHMS { year: 2030, month: 11, day: 22,
                                 hour: 13, minute: 14, second: 15 }];
            let s = series_new_ymdhms(n.as_ptr(), data.as_ptr(), data.len());
            let v = series_ref_ymdhms(s, 0);
            assert_eq!(v.valid, 1);
            assert_eq!(v.value.year, 2030);
            assert_eq!(v.value.month, 11);
            assert_eq!(v.value.day, 22);
            assert_eq!(v.value.hour, 13);
            assert_eq!(v.value.minute, 14);
            assert_eq!(v.value.second, 15);
            series_drop(s);
        }
    }

    /// `series_dtype` reports the right `CompatDType` tag/time-unit for
    /// every constructor. Spot-checks the dtype-tag table the FFI
    /// implements via `compat_dtype_from_polars`.
    mod series_dtype_tag {
        use super::*;
        use super::test_util::*;

        #[test]
        fn dtype_each_int_width() {
            let cases: &[(*mut Series, CompatDTypeTag)] = &[
                (make_i32("a", &[1]), CompatDTypeTag::Int32),
                (make_i64("a", &[1]), CompatDTypeTag::Int64),
            ];
            for (s, tag) in cases {
                assert_dtype(*s, *tag, CompatTimeUnit::None);
                series_drop(*s);
            }
        }

        #[test]
        fn dtype_each_float_width() {
            let s64 = make_f64("a", &[1.0]);
            assert_dtype(s64, CompatDTypeTag::Float64, CompatTimeUnit::None);
            series_drop(s64);

            // f32 needs a direct ctor call since no test_util helper exists.
            let n = cstr("a");
            let data: [f32; 1] = [1.0];
            let s32 = series_new_f32(n.as_ptr(), data.as_ptr(), data.len());
            assert_dtype(s32, CompatDTypeTag::Float32, CompatTimeUnit::None);
            series_drop(s32);
        }

        #[test]
        fn dtype_bool_and_string() {
            let b = make_bool("b", &[1, 0]);
            assert_dtype(b, CompatDTypeTag::Boolean, CompatTimeUnit::None);
            series_drop(b);
            let s = make_str("s", &["x"]);
            assert_dtype(s, CompatDTypeTag::String, CompatTimeUnit::None);
            series_drop(s);
        }
    }

    // ===== R3: Series ops =====

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

    /// Scalar comparison externs: `series_{lt,le,gt,ge,eq,ne}_{i32,f64}`
    /// plus the `_str` equality variants. Each test collects the bool
    /// result vector and asserts the expected mask.
    mod series_cmp_scalar {
        use super::*;
        use super::test_util::*;

        #[test]
        fn cmp_i32_all_ops_against_scalar() {
            let s = make_i32("xs", &[1, 2, 3, 4]);
            let lt = series_lt_i32(s, 3);
            assert_eq!(read_bool_series(lt), vec![true, true, false, false]);
            series_drop(lt);
            let le = series_le_i32(s, 3);
            assert_eq!(read_bool_series(le), vec![true, true, true, false]);
            series_drop(le);
            let gt = series_gt_i32(s, 3);
            assert_eq!(read_bool_series(gt), vec![false, false, false, true]);
            series_drop(gt);
            let ge = series_ge_i32(s, 3);
            assert_eq!(read_bool_series(ge), vec![false, false, true, true]);
            series_drop(ge);
            let eq = series_eq_i32(s, 3);
            assert_eq!(read_bool_series(eq), vec![false, false, true, false]);
            series_drop(eq);
            let ne = series_ne_i32(s, 3);
            assert_eq!(read_bool_series(ne), vec![true, true, false, true]);
            series_drop(ne);
            series_drop(s);
        }

        #[test]
        fn cmp_f64_all_ops_against_scalar() {
            let s = make_f64("ys", &[1.5, 2.5, 3.5]);
            let lt = series_lt_f64(s, 2.5);
            assert_eq!(read_bool_series(lt), vec![true, false, false]);
            series_drop(lt);
            let eq = series_eq_f64(s, 2.5);
            assert_eq!(read_bool_series(eq), vec![false, true, false]);
            series_drop(eq);
            let ge = series_ge_f64(s, 2.5);
            assert_eq!(read_bool_series(ge), vec![false, true, true]);
            series_drop(ge);
            series_drop(s);
        }

        #[test]
        fn cmp_str_eq_and_ne() {
            let s = make_str("ws", &["a", "b", "a"]);
            let rhs = cstr("a");
            let eq = series_eq_str(s, rhs.as_ptr());
            assert_eq!(read_bool_series(eq), vec![true, false, true]);
            series_drop(eq);
            let ne = series_ne_str(s, rhs.as_ptr());
            assert_eq!(read_bool_series(ne), vec![false, true, false]);
            series_drop(ne);
            series_drop(s);
        }

        #[test]
        fn cmp_scalar_null_series_returns_null() {
            assert!(series_lt_i32(ptr::null_mut(), 0).is_null());
            assert!(series_eq_f64(ptr::null_mut(), 0.0).is_null());
            let rhs = cstr("a");
            assert!(series_eq_str(ptr::null_mut(), rhs.as_ptr()).is_null());
        }

        #[test]
        fn cmp_str_null_rhs_returns_null() {
            let s = make_str("ws", &["a"]);
            assert!(series_eq_str(s, ptr::null()).is_null());
            series_drop(s);
        }
    }

    /// Series-vs-series comparison externs.
    mod series_cmp_series {
        use super::*;
        use super::test_util::*;

        #[test]
        fn eq_ne_gt_ge_lt_le_against_series() {
            let a = make_i32("a", &[1, 2, 3, 4]);
            let b = make_i32("b", &[2, 2, 2, 5]);
            let eq = series_eq(a, b);
            assert_eq!(read_bool_series(eq), vec![false, true, false, false]);
            series_drop(eq);
            let ne = series_ne(a, b);
            assert_eq!(read_bool_series(ne), vec![true, false, true, true]);
            series_drop(ne);
            let gt = series_gt(a, b);
            assert_eq!(read_bool_series(gt), vec![false, false, true, false]);
            series_drop(gt);
            let ge = series_ge(a, b);
            assert_eq!(read_bool_series(ge), vec![false, true, true, false]);
            series_drop(ge);
            let lt = series_lt(a, b);
            assert_eq!(read_bool_series(lt), vec![true, false, false, true]);
            series_drop(lt);
            let le = series_le(a, b);
            assert_eq!(read_bool_series(le), vec![true, true, false, true]);
            series_drop(le);
            series_drop(a);
            series_drop(b);
        }

        #[test]
        fn cmp_series_null_inputs_return_null() {
            let s = make_i32("a", &[1]);
            assert!(series_eq(ptr::null_mut(), s).is_null());
            assert!(series_eq(s, ptr::null_mut()).is_null());
            series_drop(s);
        }
    }

    /// Scalar arithmetic family `series_{add,sub,mul,div,mod}_{i32,i64,
    /// u32,u64,f64}`.
    mod series_arith_scalar {
        use super::*;
        use super::test_util::*;

        fn read_i32(s: *mut Series) -> Vec<i32> {
            (0..series_len(s))
                .map(|i| {
                    let v = series_ref_i32(s, i);
                    assert_eq!(v.valid, 1);
                    v.value
                })
                .collect()
        }

        fn read_f64(s: *mut Series) -> Vec<f64> {
            (0..series_len(s))
                .map(|i| {
                    let v = series_ref_f64(s, i);
                    assert_eq!(v.valid, 1);
                    v.value
                })
                .collect()
        }

        #[test]
        fn arith_i32_family_against_scalar() {
            let s = make_i32("xs", &[10, 20, 30]);
            let add = series_add_i32(s, 5);
            assert_eq!(read_i32(add), vec![15, 25, 35]);
            series_drop(add);
            let sub = series_sub_i32(s, 5);
            assert_eq!(read_i32(sub), vec![5, 15, 25]);
            series_drop(sub);
            let mul = series_mul_i32(s, 2);
            assert_eq!(read_i32(mul), vec![20, 40, 60]);
            series_drop(mul);
            let div = series_div_i32(s, 5);
            // i32 / i32 stays i32 (integer division).
            assert_eq!(read_i32(div), vec![2, 4, 6]);
            series_drop(div);
            let rem = series_mod_i32(s, 7);
            assert_eq!(read_i32(rem), vec![3, 6, 2]);
            series_drop(rem);
            series_drop(s);
        }

        #[test]
        fn arith_f64_family_against_scalar() {
            let s = make_f64("ys", &[1.0, 2.0, 4.0]);
            let add = series_add_f64(s, 0.5);
            assert_eq!(read_f64(add), vec![1.5, 2.5, 4.5]);
            series_drop(add);
            let div = series_div_f64(s, 4.0);
            assert_eq!(read_f64(div), vec![0.25, 0.5, 1.0]);
            series_drop(div);
            series_drop(s);
        }

        #[test]
        fn arith_i64_add_smoke() {
            let s = make_i64("ys", &[1, 2, 3]);
            let add = series_add_i64(s, 10);
            let v0 = series_ref_i64(add, 0);
            assert_eq!(v0.valid, 1);
            assert_eq!(v0.value, 11);
            assert_eq!(series_ref_i64(add, 2).value, 13);
            series_drop(add);
            series_drop(s);
        }

        #[test]
        fn arith_u32_mul_smoke() {
            let n = cstr("xs");
            let data: [u32; 3] = [1, 2, 3];
            let s = series_new_u32(n.as_ptr(), data.as_ptr(), data.len());
            let mul = series_mul_u32(s, 4);
            assert_eq!(series_ref_u32(mul, 0).value, 4);
            assert_eq!(series_ref_u32(mul, 2).value, 12);
            series_drop(mul);
            series_drop(s);
        }

        #[test]
        fn arith_scalar_null_series_returns_null() {
            assert!(series_add_i32(ptr::null_mut(), 1).is_null());
            assert!(series_div_f64(ptr::null_mut(), 1.0).is_null());
        }
    }

    /// Series-vs-series arithmetic externs.
    mod series_arith_series {
        use super::*;
        use super::test_util::*;

        #[test]
        fn arith_series_add_i32() {
            let a = make_i32("a", &[1, 2, 3]);
            let b = make_i32("b", &[10, 20, 30]);
            let sum = series_add(a, b);
            let s0 = series_ref_i32(sum, 0);
            assert_eq!(s0.valid, 1);
            assert_eq!(s0.value, 11);
            assert_eq!(series_ref_i32(sum, 2).value, 33);
            series_drop(sum);
            series_drop(a);
            series_drop(b);
        }

        #[test]
        fn arith_series_sub_f64() {
            let a = make_f64("a", &[5.0, 7.0]);
            let b = make_f64("b", &[1.5, 2.5]);
            let diff = series_sub(a, b);
            assert_eq!(series_ref_f64(diff, 0).value, 3.5);
            assert_eq!(series_ref_f64(diff, 1).value, 4.5);
            series_drop(diff);
            series_drop(a);
            series_drop(b);
        }

        #[test]
        fn arith_series_div_f64_keeps_fractions() {
            let a = make_f64("a", &[1.0, 3.0]);
            let b = make_f64("b", &[4.0, 4.0]);
            let q = series_div(a, b);
            assert_eq!(series_ref_f64(q, 0).value, 0.25);
            assert_eq!(series_ref_f64(q, 1).value, 0.75);
            series_drop(q);
            series_drop(a);
            series_drop(b);
        }

        #[test]
        fn arith_series_null_input_returns_null() {
            let a = make_i32("a", &[1]);
            assert!(series_add(ptr::null_mut(), a).is_null());
            assert!(series_add(a, ptr::null_mut()).is_null());
            series_drop(a);
        }
    }

    /// Boolean ops and null predicates.
    mod series_boolean {
        use super::*;
        use super::test_util::*;

        #[test]
        fn and_or_xor_against_series() {
            let a = make_bool("a", &[1, 1, 0, 0]);
            let b = make_bool("b", &[1, 0, 1, 0]);
            let and = series_and(a, b);
            assert_eq!(read_bool_series(and), vec![true, false, false, false]);
            series_drop(and);
            let or = series_or(a, b);
            assert_eq!(read_bool_series(or), vec![true, true, true, false]);
            series_drop(or);
            let xor = series_xor(a, b);
            assert_eq!(read_bool_series(xor), vec![false, true, true, false]);
            series_drop(xor);
            series_drop(a);
            series_drop(b);
        }

        #[test]
        fn not_inverts_bool_series() {
            let a = make_bool("a", &[1, 0, 1]);
            let nb = series_not(a);
            assert_eq!(read_bool_series(nb), vec![false, true, false]);
            series_drop(nb);
            series_drop(a);
        }

        #[test]
        fn is_null_and_is_not_null_on_nullable_series() {
            let s = make_opt_i32("xs", &[Some(1), None, Some(3)]);
            let isn = series_is_null(s);
            assert_eq!(read_bool_series(isn), vec![false, true, false]);
            series_drop(isn);
            let notn = series_is_not_null(s);
            assert_eq!(read_bool_series(notn), vec![true, false, true]);
            series_drop(notn);
            series_drop(s);
        }

        #[test]
        fn boolean_ops_null_inputs_return_null() {
            let a = make_bool("a", &[1]);
            assert!(series_and(ptr::null_mut(), a).is_null());
            assert!(series_and(a, ptr::null_mut()).is_null());
            assert!(series_not(ptr::null_mut()).is_null());
            assert!(series_is_null(ptr::null_mut()).is_null());
            assert!(series_is_not_null(ptr::null_mut()).is_null());
            series_drop(a);
        }
    }

    /// Reductions: typed `series_{sum,min,max,mean}_*` for every width,
    /// plus `series_std` / `series_var` / `series_n_unique`.
    mod series_reductions {
        use super::*;
        use super::test_util::*;

        #[test]
        fn reductions_i32() {
            let s = make_i32("xs", &[1, 2, 3, 4]);
            assert_eq!(series_sum_i32(s).value, 10);
            assert_eq!(series_min_i32(s).value, 1);
            assert_eq!(series_max_i32(s).value, 4);
            assert_eq!(series_mean_i32(s).value, 2.5);
            assert_eq!(series_n_unique(s), 4);
            series_drop(s);
        }

        #[test]
        fn reductions_f64() {
            let s = make_f64("ys", &[1.0, 2.0, 3.0, 4.0]);
            assert_eq!(series_sum_f64(s).value, 10.0);
            assert_eq!(series_min_f64(s).value, 1.0);
            assert_eq!(series_max_f64(s).value, 4.0);
            assert_eq!(series_mean_f64(s).value, 2.5);
            series_drop(s);
        }

        #[test]
        fn reductions_each_int_width_sum() {
            // Hit every typed reduction the series_int_reductions! macro
            // expands to, so a future macro mistake on any width breaks.
            macro_rules! check_sum {
                ($ctor:ident, $sum:ident, $ty:ty, $expected:expr) => {{
                    let n = cstr("xs");
                    let data: [$ty; 3] = [1, 2, 3];
                    let s = $ctor(n.as_ptr(), data.as_ptr(), data.len());
                    let v = $sum(s);
                    assert_eq!(v.valid, 1);
                    assert_eq!(v.value as i64, $expected as i64);
                    series_drop(s);
                }};
            }
            check_sum!(series_new_i8,  series_sum_i8,  i8,  6i64);
            check_sum!(series_new_i16, series_sum_i16, i16, 6i64);
            check_sum!(series_new_i64, series_sum_i64, i64, 6i64);
            check_sum!(series_new_u8,  series_sum_u8,  u8,  6i64);
            check_sum!(series_new_u16, series_sum_u16, u16, 6i64);
            check_sum!(series_new_u32, series_sum_u32, u32, 6i64);
            check_sum!(series_new_u64, series_sum_u64, u64, 6i64);
        }

        #[test]
        fn reductions_f32() {
            let n = cstr("ys");
            let data: [f32; 4] = [1.0, 2.0, 3.0, 4.0];
            let s = series_new_f32(n.as_ptr(), data.as_ptr(), data.len());
            assert_eq!(series_sum_f32(s).value, 10.0);
            assert_eq!(series_min_f32(s).value, 1.0);
            assert_eq!(series_max_f32(s).value, 4.0);
            assert_eq!(series_mean_f32(s).value, 2.5);
            series_drop(s);
        }

        #[test]
        fn std_var_defaults_to_ddof_1() {
            // [2,4,4,4,5,5,7,9]: sample variance = 32/7 ≈ 4.571.
            let s = make_f64("ys", &[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]);
            let var1 = series_var(s, 1);
            assert_eq!(var1.valid, 1);
            assert!((var1.value - (32.0 / 7.0)).abs() < 1e-9);
            let std1 = series_std(s, 1);
            assert_eq!(std1.valid, 1);
            assert!((std1.value - (32.0 / 7.0_f64).sqrt()).abs() < 1e-9);
            // ddof=0 (population) = 32/8 = 4.0.
            let var0 = series_var(s, 0);
            assert!((var0.value - 4.0).abs() < 1e-9);
            series_drop(s);
        }

        #[test]
        fn n_unique_counts_distinct_entries() {
            let s = make_i32("xs", &[1, 2, 2, 3, 3, 3]);
            assert_eq!(series_n_unique(s), 3);
            series_drop(s);
        }

        #[test]
        fn reductions_all_null_series() {
            // All-null nullable integer series: Polars treats the sum
            // of "nothing" as Some(0), but min / max / mean return
            // None (valid=0).
            let s = make_opt_i32("xs", &[None, None, None]);
            let sum = series_sum_i32(s);
            assert_eq!(sum.valid, 1);
            assert_eq!(sum.value, 0);
            assert_eq!(series_min_i32(s).valid, 0);
            assert_eq!(series_max_i32(s).valid, 0);
            assert_eq!(series_mean_i32(s).valid, 0);
            series_drop(s);
        }

        #[test]
        fn reductions_null_series_return_none() {
            assert_eq!(series_sum_i32(ptr::null_mut()).valid, 0);
            assert_eq!(series_mean_f64(ptr::null_mut()).valid, 0);
            assert_eq!(series_std(ptr::null_mut(), 1).valid, 0);
            assert_eq!(series_var(ptr::null_mut(), 1).valid, 0);
            assert_eq!(series_n_unique(ptr::null_mut()), 0);
        }
    }

    /// Reshaping ops: head / tail / slice / reverse / drop_nulls /
    /// unique / sort.
    mod series_reshaping {
        use super::*;
        use super::test_util::*;

        #[test]
        fn head_returns_first_n() {
            let s = make_i32("xs", &[1, 2, 3, 4, 5]);
            let h = series_head(s, 2);
            assert_eq!(series_len(h), 2);
            assert_eq!(series_ref_i32(h, 0).value, 1);
            assert_eq!(series_ref_i32(h, 1).value, 2);
            series_drop(h);
            series_drop(s);
        }

        #[test]
        fn tail_returns_last_n() {
            let s = make_i32("xs", &[1, 2, 3, 4, 5]);
            let t = series_tail(s, 2);
            assert_eq!(series_len(t), 2);
            assert_eq!(series_ref_i32(t, 0).value, 4);
            assert_eq!(series_ref_i32(t, 1).value, 5);
            series_drop(t);
            series_drop(s);
        }

        #[test]
        fn slice_offset_length() {
            let s = make_i32("xs", &[10, 20, 30, 40, 50]);
            let sl = series_slice(s, 1, 3);
            assert_eq!(series_len(sl), 3);
            assert_eq!(series_ref_i32(sl, 0).value, 20);
            assert_eq!(series_ref_i32(sl, 2).value, 40);
            series_drop(sl);
            series_drop(s);
        }

        #[test]
        fn reverse_reverses_order() {
            let s = make_i32("xs", &[1, 2, 3]);
            let r = series_reverse(s);
            assert_eq!(series_ref_i32(r, 0).value, 3);
            assert_eq!(series_ref_i32(r, 2).value, 1);
            series_drop(r);
            series_drop(s);
        }

        #[test]
        fn drop_nulls_collapses_length() {
            let s = make_opt_i32("xs", &[Some(1), None, Some(3), None, Some(5)]);
            let d = series_drop_nulls(s);
            assert_eq!(series_len(d), 3);
            // The remaining values keep their order.
            assert_eq!(series_ref_i32(d, 0).value, 1);
            assert_eq!(series_ref_i32(d, 1).value, 3);
            assert_eq!(series_ref_i32(d, 2).value, 5);
            series_drop(d);
            series_drop(s);
        }

        #[test]
        fn unique_dedupes_entries() {
            let s = make_i32("xs", &[1, 2, 2, 3, 3, 3]);
            let u = series_unique(s);
            // Order isn't guaranteed; check the count + sum.
            assert_eq!(series_len(u), 3);
            let mut got: Vec<i32> = (0..series_len(u))
                .map(|i| series_ref_i32(u, i).value)
                .collect();
            got.sort();
            assert_eq!(got, vec![1, 2, 3]);
            series_drop(u);
            series_drop(s);
        }

        #[test]
        fn sort_ascending_and_descending() {
            let s = make_i32("xs", &[3, 1, 2]);
            let asc = series_sort(s, 0);
            assert_eq!(series_ref_i32(asc, 0).value, 1);
            assert_eq!(series_ref_i32(asc, 2).value, 3);
            series_drop(asc);
            let desc = series_sort(s, 1);
            assert_eq!(series_ref_i32(desc, 0).value, 3);
            assert_eq!(series_ref_i32(desc, 2).value, 1);
            series_drop(desc);
            series_drop(s);
        }

        #[test]
        fn reshaping_null_series_returns_null() {
            assert!(series_head(ptr::null_mut(), 1).is_null());
            assert!(series_tail(ptr::null_mut(), 1).is_null());
            assert!(series_slice(ptr::null_mut(), 0, 1).is_null());
            assert!(series_reverse(ptr::null_mut()).is_null());
            assert!(series_drop_nulls(ptr::null_mut()).is_null());
            assert!(series_unique(ptr::null_mut()).is_null());
            assert!(series_sort(ptr::null_mut(), 0).is_null());
        }
    }

    /// `series_cast`: happy paths for numeric → numeric and numeric →
    /// string, plus the rejected-target-tag and null-series refusals
    /// (the temporal cast paths are covered by R2's `mod
    /// series_value_access`).
    mod series_cast_tests {
        use super::*;
        use super::test_util::*;

        fn dtype(tag: CompatDTypeTag, tu: CompatTimeUnit) -> CompatDType {
            CompatDType {
                tag: tag as i32,
                time_unit: tu as i32,
                flags: 0,
                array_width: 0,
            }
        }

        #[test]
        fn cast_i32_to_i64_changes_dtype() {
            let s = make_i32("xs", &[1, 2, 3]);
            let out = series_cast(
                s,
                dtype(CompatDTypeTag::Int64, CompatTimeUnit::None),
            );
            assert!(!out.is_null());
            assert_dtype(out, CompatDTypeTag::Int64, CompatTimeUnit::None);
            assert_eq!(series_ref_i64(out, 0).value, 1);
            assert_eq!(series_ref_i64(out, 2).value, 3);
            series_drop(out);
            series_drop(s);
        }

        #[test]
        fn cast_f64_to_i32_truncates() {
            let s = make_f64("ys", &[1.7, 2.2, -3.9]);
            let out = series_cast(
                s,
                dtype(CompatDTypeTag::Int32, CompatTimeUnit::None),
            );
            assert!(!out.is_null());
            assert_dtype(out, CompatDTypeTag::Int32, CompatTimeUnit::None);
            // Polars f64 -> i32 truncates toward zero.
            assert_eq!(series_ref_i32(out, 0).value, 1);
            assert_eq!(series_ref_i32(out, 1).value, 2);
            assert_eq!(series_ref_i32(out, 2).value, -3);
            series_drop(out);
            series_drop(s);
        }

        #[test]
        fn cast_i32_to_string_produces_string_series() {
            let s = make_i32("xs", &[1, 2, 3]);
            let out = series_cast(
                s,
                dtype(CompatDTypeTag::String, CompatTimeUnit::None),
            );
            assert!(!out.is_null());
            assert_dtype(out, CompatDTypeTag::String, CompatTimeUnit::None);
            assert_eq!(take_cstring(series_ref_str(out, 0)), "1");
            assert_eq!(take_cstring(series_ref_str(out, 2)), "3");
            series_drop(out);
            series_drop(s);
        }

        #[test]
        fn cast_rejected_target_tag_returns_null() {
            // List is accepted on output but not as a cast target, so
            // polars_dtype_from_compat returns None and series_cast must
            // produce a null pointer rather than panic.
            let s = make_i32("xs", &[1]);
            let out = series_cast(
                s,
                dtype(CompatDTypeTag::List, CompatTimeUnit::None),
            );
            assert!(out.is_null());
            series_drop(s);
        }

        #[test]
        fn cast_null_series_returns_null() {
            let out = series_cast(
                ptr::null_mut(),
                dtype(CompatDTypeTag::Int64, CompatTimeUnit::None),
            );
            assert!(out.is_null());
        }
    }

    // ===== R4: DataFrame core =====

    /// `dataframe_*` lifecycle, shape, column access, row/column
    /// reshaping, filter / sort / unique / drop_nulls.
    mod dataframe_core {
        use super::*;
        use super::test_util::*;

        /// Build a tiny 2-column DataFrame: i32 `x` + str `g`. Returns
        /// the DataFrame and the input Series so the caller can drop
        /// everything cleanly.
        fn make_xg(
            x: &[i32],
            g: &[&str],
        ) -> (*mut DataFrame, *mut Series, *mut Series) {
            let xs = make_i32("x", x);
            let gs = make_str("g", g);
            let df = make_df(&[xs, gs]);
            (df, xs, gs)
        }

        // --- lifecycle / construction -------------------------------------

        #[test]
        fn empty_dataframe_has_zero_shape() {
            let df = dataframe_empty();
            assert!(!df.is_null());
            assert_eq!(dataframe_height(df), 0);
            assert_eq!(dataframe_width(df), 0);
            dataframe_drop(df);
        }

        #[test]
        fn dataframe_make_and_drop_no_op() {
            // `dataframe_make` produces a default DataFrame and the
            // matching drop must accept a null pointer without panicking.
            let df = dataframe_make();
            assert!(!df.is_null());
            dataframe_drop(df);
            dataframe_drop(ptr::null_mut());
        }

        #[test]
        fn dataframe_new_with_columns_sets_shape() {
            let (df, xs, gs) = make_xg(&[1, 2, 3], &["a", "b", "c"]);
            assert_eq!(dataframe_height(df), 3);
            assert_eq!(dataframe_width(df), 2);
            let sh = dataframe_shape(df);
            assert_eq!(sh.rows, 3);
            assert_eq!(sh.cols, 2);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn dataframe_new_null_ptr_array_returns_null() {
            let df = dataframe_new(ptr::null(), 3);
            assert!(df.is_null());
        }

        #[test]
        fn dataframe_new_with_null_series_in_array_returns_null() {
            let xs = make_i32("x", &[1, 2]);
            let ptrs: [*const Series; 2] = [xs as *const _, ptr::null()];
            let df = dataframe_new(ptrs.as_ptr(), ptrs.len());
            assert!(df.is_null());
            series_drop(xs);
        }

        #[test]
        fn dataframe_new_mismatched_lengths_returns_null() {
            // Two columns of unequal length is a Polars error and must
            // surface as a null pointer, not a panic.
            let xs = make_i32("x", &[1, 2, 3]);
            let ys = make_i32("y", &[10, 20]);
            let ptrs: [*const Series; 2] =
                [xs as *const _, ys as *const _];
            let df = dataframe_new(ptrs.as_ptr(), ptrs.len());
            assert!(df.is_null());
            series_drop(xs);
            series_drop(ys);
        }

        #[test]
        fn dataframe_new_empty_array_is_ok() {
            let df = dataframe_new(ptr::null(), 0);
            assert!(!df.is_null());
            assert_eq!(dataframe_height(df), 0);
            assert_eq!(dataframe_width(df), 0);
            dataframe_drop(df);
        }

        // --- shape / metadata on null pointer ----------------------------

        #[test]
        fn height_and_width_on_null_df_return_zero() {
            assert_eq!(dataframe_height(ptr::null_mut()), 0);
            assert_eq!(dataframe_width(ptr::null_mut()), 0);
        }

        #[test]
        fn shape_on_null_df_returns_zero_zero() {
            let sh = dataframe_shape(ptr::null_mut());
            assert_eq!(sh.rows, 0);
            assert_eq!(sh.cols, 0);
        }

        // --- column access -----------------------------------------------

        #[test]
        fn column_name_returns_each_name() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            assert_eq!(read_column_names(df), vec!["x", "g"]);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn column_name_out_of_range_returns_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            assert!(dataframe_column_name(df, 99).is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn column_returns_cloned_series_by_name() {
            let (df, xs, gs) = make_xg(&[10, 20, 30], &["a", "b", "c"]);
            let n = cstr("x");
            let col = dataframe_column(df, n.as_ptr());
            assert!(!col.is_null());
            assert_eq!(series_len(col), 3);
            assert_eq!(series_ref_i32(col, 1).value, 20);
            // The returned series is independent: dropping it leaves df
            // intact.
            series_drop(col);
            assert_eq!(dataframe_height(df), 3);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn column_unknown_name_returns_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            let n = cstr("nope");
            assert!(dataframe_column(df, n.as_ptr()).is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn column_null_inputs_return_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            assert!(dataframe_column(df, ptr::null()).is_null());
            assert!(dataframe_column(ptr::null_mut(),
                                     cstr("x").as_ptr()).is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        // --- row-shaping -------------------------------------------------

        #[test]
        fn head_returns_first_n_rows() {
            let (df, xs, gs) = make_xg(&[1, 2, 3, 4, 5],
                                       &["a", "b", "c", "d", "e"]);
            let h = dataframe_head(df, 2);
            assert_eq!(dataframe_height(h), 2);
            assert_eq!(read_i32_col(h, "x"), vec![1, 2]);
            dataframe_drop(h);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn tail_returns_last_n_rows() {
            let (df, xs, gs) = make_xg(&[1, 2, 3, 4, 5],
                                       &["a", "b", "c", "d", "e"]);
            let t = dataframe_tail(df, 2);
            assert_eq!(dataframe_height(t), 2);
            assert_eq!(read_i32_col(t, "x"), vec![4, 5]);
            dataframe_drop(t);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn slice_offset_length_picks_window() {
            let (df, xs, gs) = make_xg(&[10, 20, 30, 40, 50],
                                       &["a", "b", "c", "d", "e"]);
            let sl = dataframe_slice(df, 1, 3);
            assert_eq!(dataframe_height(sl), 3);
            assert_eq!(read_i32_col(sl, "x"), vec![20, 30, 40]);
            dataframe_drop(sl);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn row_shaping_on_null_df_returns_null() {
            assert!(dataframe_head(ptr::null_mut(), 1).is_null());
            assert!(dataframe_tail(ptr::null_mut(), 1).is_null());
            assert!(dataframe_slice(ptr::null_mut(), 0, 1).is_null());
        }

        // --- column ops --------------------------------------------------

        #[test]
        fn select_returns_named_columns_in_order() {
            let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
            let g_name = cstr("g");
            let x_name = cstr("x");
            let names: [*const c_char; 2] = [g_name.as_ptr(), x_name.as_ptr()];
            let out = dataframe_select(df, names.as_ptr(), names.len());
            assert!(!out.is_null());
            assert_eq!(read_column_names(out), vec!["g", "x"]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn select_unknown_name_returns_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            let n = cstr("nope");
            let names: [*const c_char; 1] = [n.as_ptr()];
            let out = dataframe_select(df, names.as_ptr(), names.len());
            assert!(out.is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn drop_columns_removes_named() {
            let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
            let g_name = cstr("g");
            let names: [*const c_char; 1] = [g_name.as_ptr()];
            let out =
                dataframe_drop_columns(df, names.as_ptr(), names.len());
            assert!(!out.is_null());
            assert_eq!(read_column_names(out), vec!["x"]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn drop_columns_unknown_returns_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            let n = cstr("nope");
            let names: [*const c_char; 1] = [n.as_ptr()];
            let out =
                dataframe_drop_columns(df, names.as_ptr(), names.len());
            assert!(out.is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn rename_changes_column_name() {
            let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
            let old = cstr("g");
            let new = cstr("group");
            let out = dataframe_rename(df, old.as_ptr(), new.as_ptr());
            assert!(!out.is_null());
            assert_eq!(read_column_names(out), vec!["x", "group"]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn rename_unknown_column_returns_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            let old = cstr("nope");
            let new = cstr("group");
            let out = dataframe_rename(df, old.as_ptr(), new.as_ptr());
            assert!(out.is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn with_column_appends_new_column() {
            let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
            let extra = make_i32("y", &[100, 200]);
            let out = dataframe_with_column(df, extra);
            assert!(!out.is_null());
            assert_eq!(read_column_names(out), vec!["x", "g", "y"]);
            assert_eq!(read_i32_col(out, "y"), vec![100, 200]);
            dataframe_drop(out);
            series_drop(extra);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn with_column_replaces_existing_column_in_place() {
            // A column named "x" already exists; `with_column` should
            // replace it rather than appending a duplicate.
            let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
            let replacement = make_i32("x", &[42, 84]);
            let out = dataframe_with_column(df, replacement);
            assert!(!out.is_null());
            assert_eq!(dataframe_width(out), 2);
            assert_eq!(read_column_names(out), vec!["x", "g"]);
            assert_eq!(read_i32_col(out, "x"), vec![42, 84]);
            dataframe_drop(out);
            series_drop(replacement);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        // --- filter / sort -----------------------------------------------

        #[test]
        fn filter_with_bool_mask_keeps_true_rows() {
            let (df, xs, gs) =
                make_xg(&[1, 2, 3, 4], &["a", "b", "c", "d"]);
            // Mask = x > 2: keep rows 3 and 4.
            let mask = series_gt_i32(xs, 2);
            let out = dataframe_filter(df, mask);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 2);
            assert_eq!(read_i32_col(out, "x"), vec![3, 4]);
            dataframe_drop(out);
            series_drop(mask);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn filter_null_mask_returns_null() {
            let (df, xs, gs) = make_xg(&[1], &["a"]);
            assert!(dataframe_filter(df, ptr::null_mut()).is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn filter_non_bool_mask_returns_null() {
            // Passing an i32 series as the mask is a polars type error
            // that the wrapper must surface as a null pointer.
            let (df, xs, gs) = make_xg(&[1, 2], &["a", "b"]);
            assert!(dataframe_filter(df, xs).is_null());
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn sort_ascending_and_descending() {
            let (df, xs, gs) = make_xg(&[3, 1, 2], &["a", "b", "c"]);
            let by = cstr("x");
            let by_arr: [*const c_char; 1] = [by.as_ptr()];

            let asc =
                dataframe_sort(df, by_arr.as_ptr(), ptr::null(), by_arr.len());
            assert!(!asc.is_null());
            assert_eq!(read_i32_col(asc, "x"), vec![1, 2, 3]);
            dataframe_drop(asc);

            let desc_flag: [u8; 1] = [1];
            let desc = dataframe_sort(
                df,
                by_arr.as_ptr(),
                desc_flag.as_ptr(),
                by_arr.len(),
            );
            assert!(!desc.is_null());
            assert_eq!(read_i32_col(desc, "x"), vec![3, 2, 1]);
            dataframe_drop(desc);

            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn sort_two_keys_with_descending_flags() {
            // Sort by g ascending, then x descending: groups of g come
            // out in 'a','b' order; within each group x is reversed.
            let g_a = cstr("g");
            let x_n = cstr("x");
            let by_arr: [*const c_char; 2] = [g_a.as_ptr(), x_n.as_ptr()];
            let desc_flags: [u8; 2] = [0, 1];

            let (df, xs, gs) =
                make_xg(&[1, 2, 3, 4], &["b", "a", "b", "a"]);
            let out = dataframe_sort(
                df,
                by_arr.as_ptr(),
                desc_flags.as_ptr(),
                by_arr.len(),
            );
            assert!(!out.is_null());
            // After sort: g = a a b b, x = 4 2 3 1.
            assert_eq!(read_i32_col(out, "x"), vec![4, 2, 3, 1]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn sort_null_df_returns_null() {
            let by = cstr("x");
            let by_arr: [*const c_char; 1] = [by.as_ptr()];
            assert!(dataframe_sort(
                ptr::null_mut(),
                by_arr.as_ptr(),
                ptr::null(),
                by_arr.len()
            )
            .is_null());
        }

        // --- unique / drop_nulls -----------------------------------------

        #[test]
        fn unique_dedupes_rows() {
            let xs = make_i32("x", &[1, 1, 2, 2, 3]);
            let gs = make_str("g", &["a", "a", "b", "b", "c"]);
            let df = make_df(&[xs, gs]);
            let out = dataframe_unique(df);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 3);
            // Polars doesn't guarantee row order after `.unique()` — pull
            // x column, sort, and check the set of survivors.
            let mut got = read_i32_col(out, "x");
            got.sort();
            assert_eq!(got, vec![1, 2, 3]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn drop_nulls_removes_rows_with_any_null() {
            let xs = make_opt_i32(
                "x",
                &[Some(1), None, Some(3), Some(4)],
            );
            let gs = make_str("g", &["a", "b", "c", "d"]);
            let df = make_df(&[xs, gs]);
            let out = dataframe_drop_nulls(df);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 3);
            assert_eq!(read_i32_col(out, "x"), vec![1, 3, 4]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn unique_and_drop_nulls_null_df_return_null() {
            assert!(dataframe_unique(ptr::null_mut()).is_null());
            assert!(dataframe_drop_nulls(ptr::null_mut()).is_null());
        }
    }

    // ===== R5: DataFrame group-by + joins + reshape + IO =====

    /// Build a tiny grouped DataFrame: `g` = ["a","a","b","b","b"],
    /// `x` = [10,20,30,40,50]. Returned with the input Series so the
    /// caller can drop everything cleanly.
    fn make_gx() -> (*mut DataFrame, *mut Series, *mut Series) {
        let gs = tests::test_util::make_str("g", &["a", "a", "b", "b", "b"]);
        let xs = tests::test_util::make_i32("x", &[10, 20, 30, 40, 50]);
        let df = tests::test_util::make_df(&[gs, xs]);
        (df, gs, xs)
    }

    /// Group-by aggregation family (`dataframe_group_by_{sum,mean,min,
    /// max,count}`).
    mod dataframe_groupby {
        use super::*;
        use super::test_util::*;

        /// Wrap the by/agg name array setup that every group-by call
        /// reuses, then read back the `x` column sorted by `g`.
        fn run_group_by(
            df: *mut DataFrame,
            agg_name: &str,
            f: extern "C" fn(
                *mut DataFrame,
                *const *const c_char,
                usize,
                *const *const c_char,
                usize,
            ) -> *mut DataFrame,
        ) -> *mut DataFrame {
            let by_g = cstr("g");
            let by_arr: [*const c_char; 1] = [by_g.as_ptr()];
            let agg = cstr(agg_name);
            let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
            let out = f(
                df,
                by_arr.as_ptr(),
                by_arr.len(),
                agg_arr.as_ptr(),
                agg_arr.len(),
            );
            assert!(!out.is_null(), "group_by returned null");
            out
        }

        /// Sort the group-by result by `g` so the test reads back in a
        /// deterministic order — Polars' group_by output ordering is
        /// not guaranteed.
        fn sorted_by_g(df: *mut DataFrame) -> *mut DataFrame {
            let g = cstr("g");
            let by: [*const c_char; 1] = [g.as_ptr()];
            dataframe_sort(df, by.as_ptr(), ptr::null(), by.len())
        }

        // Polars 0.41 renames the aggregated column by suffixing the
        // op name — `group_by_sum` on column `x` produces `x_sum`, etc.

        #[test]
        fn group_by_sum_aggregates_per_key() {
            let (df, gs, xs) = make_gx();
            let raw = run_group_by(df, "x", dataframe_group_by_sum);
            let out = sorted_by_g(raw);
            assert_eq!(dataframe_height(out), 2);
            // a -> 10+20 = 30; b -> 30+40+50 = 120.
            assert_eq!(read_i32_col(out, "x_sum"), vec![30, 120]);
            dataframe_drop(out);
            dataframe_drop(raw);
            dataframe_drop(df);
            series_drop(gs);
            series_drop(xs);
        }

        #[test]
        fn group_by_min_and_max() {
            let (df, gs, xs) = make_gx();
            let raw_min = run_group_by(df, "x", dataframe_group_by_min);
            let out_min = sorted_by_g(raw_min);
            assert_eq!(read_i32_col(out_min, "x_min"), vec![10, 30]);
            dataframe_drop(out_min);
            dataframe_drop(raw_min);

            let raw_max = run_group_by(df, "x", dataframe_group_by_max);
            let out_max = sorted_by_g(raw_max);
            assert_eq!(read_i32_col(out_max, "x_max"), vec![20, 50]);
            dataframe_drop(out_max);
            dataframe_drop(raw_max);

            dataframe_drop(df);
            series_drop(gs);
            series_drop(xs);
        }

        #[test]
        fn group_by_mean_produces_f64_column() {
            let (df, gs, xs) = make_gx();
            let raw = run_group_by(df, "x", dataframe_group_by_mean);
            let out = sorted_by_g(raw);
            // a -> 15.0, b -> 40.0
            let n = cstr("x_mean");
            let col = dataframe_column(out, n.as_ptr());
            assert!(!col.is_null(), "x_mean column missing");
            assert_eq!(series_ref_f64(col, 0).value, 15.0);
            assert_eq!(series_ref_f64(col, 1).value, 40.0);
            series_drop(col);
            dataframe_drop(out);
            dataframe_drop(raw);
            dataframe_drop(df);
            series_drop(gs);
            series_drop(xs);
        }

        #[test]
        fn group_by_count_emits_count_column() {
            let (df, gs, xs) = make_gx();
            // count produces a "<col>_count" column of u32 — the
            // outgoing column name carries the agg suffix from Polars.
            let by = cstr("g");
            let by_arr: [*const c_char; 1] = [by.as_ptr()];
            let agg = cstr("x");
            let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
            let raw = dataframe_group_by_count(
                df,
                by_arr.as_ptr(),
                by_arr.len(),
                agg_arr.as_ptr(),
                agg_arr.len(),
            );
            assert!(!raw.is_null());
            let out = sorted_by_g(raw);
            assert_eq!(dataframe_height(out), 2);
            // Either "x_count" or "x" depending on Polars version —
            // verify the row counts via the second column rather than a
            // hard-coded name.
            let names = read_column_names(out);
            assert_eq!(names.len(), 2);
            let val_name = cstr(&names[1]);
            let col = dataframe_column(out, val_name.as_ptr());
            // group `a` has 2 rows, group `b` has 3 rows. The exact int
            // type Polars picks (u32) is read via the u32 accessor.
            assert_eq!(series_ref_u32(col, 0).value, 2);
            assert_eq!(series_ref_u32(col, 1).value, 3);
            series_drop(col);
            dataframe_drop(out);
            dataframe_drop(raw);
            dataframe_drop(df);
            series_drop(gs);
            series_drop(xs);
        }

        #[test]
        fn group_by_unknown_key_returns_null() {
            let (df, gs, xs) = make_gx();
            let by = cstr("nope");
            let by_arr: [*const c_char; 1] = [by.as_ptr()];
            let agg = cstr("x");
            let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
            let out = dataframe_group_by_sum(
                df,
                by_arr.as_ptr(),
                by_arr.len(),
                agg_arr.as_ptr(),
                agg_arr.len(),
            );
            assert!(out.is_null());
            dataframe_drop(df);
            series_drop(gs);
            series_drop(xs);
        }

        #[test]
        fn group_by_null_df_returns_null() {
            let by = cstr("g");
            let by_arr: [*const c_char; 1] = [by.as_ptr()];
            let agg = cstr("x");
            let agg_arr: [*const c_char; 1] = [agg.as_ptr()];
            assert!(dataframe_group_by_sum(
                ptr::null_mut(),
                by_arr.as_ptr(),
                by_arr.len(),
                agg_arr.as_ptr(),
                agg_arr.len()
            )
            .is_null());
        }
    }

    /// `dataframe_join` enum-mapping: every `CompatJoinKind` variant
    /// produces the documented row-count behavior.
    mod dataframe_join {
        use super::*;
        use super::test_util::*;

        /// Left = {k:[1,2,3], v:[10,20,30]}.
        /// Right = {k:[2,3,4], w:[200,300,400]}.
        fn make_left_right(
        ) -> (*mut DataFrame, *mut DataFrame, [*mut Series; 4]) {
            let lk = make_i32("k", &[1, 2, 3]);
            let lv = make_i32("v", &[10, 20, 30]);
            let rk = make_i32("k", &[2, 3, 4]);
            let rw = make_i32("w", &[200, 300, 400]);
            let left = make_df(&[lk, lv]);
            let right = make_df(&[rk, rw]);
            (left, right, [lk, lv, rk, rw])
        }

        fn join_on_k(
            left: *mut DataFrame,
            right: *mut DataFrame,
            kind: CompatJoinKind,
        ) -> *mut DataFrame {
            let lk = cstr("k");
            let rk = cstr("k");
            let lon: [*const c_char; 1] = [lk.as_ptr()];
            let ron: [*const c_char; 1] = [rk.as_ptr()];
            dataframe_join(
                left,
                right,
                lon.as_ptr(),
                lon.len(),
                ron.as_ptr(),
                ron.len(),
                kind as i32,
            )
        }

        fn cleanup(
            left: *mut DataFrame,
            right: *mut DataFrame,
            series: [*mut Series; 4],
        ) {
            dataframe_drop(left);
            dataframe_drop(right);
            for s in series {
                series_drop(s);
            }
        }

        #[test]
        fn join_inner_returns_only_matches() {
            let (left, right, series) = make_left_right();
            let out = join_on_k(left, right, CompatJoinKind::Inner);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 2);
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn join_left_keeps_all_left_rows() {
            let (left, right, series) = make_left_right();
            let out = join_on_k(left, right, CompatJoinKind::Left);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 3);
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn join_outer_keeps_all_rows_from_both_sides() {
            let (left, right, series) = make_left_right();
            let out = join_on_k(left, right, CompatJoinKind::Outer);
            assert!(!out.is_null());
            // 2 matched (k=2,3) + 1 left-only (k=1) + 1 right-only (k=4)
            assert_eq!(dataframe_height(out), 4);
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn join_cross_produces_cartesian_product() {
            let (left, right, series) = make_left_right();
            // Cross join ignores the `on` arrays — pass empties.
            let out = dataframe_join(
                left,
                right,
                ptr::null(),
                0,
                ptr::null(),
                0,
                CompatJoinKind::Cross as i32,
            );
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 3 * 3);
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn join_semi_returns_left_with_matches() {
            let (left, right, series) = make_left_right();
            let out = join_on_k(left, right, CompatJoinKind::Semi);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 2);
            assert_eq!(dataframe_width(out), 2); // semi returns left cols
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn join_anti_returns_left_without_matches() {
            let (left, right, series) = make_left_right();
            let out = join_on_k(left, right, CompatJoinKind::Anti);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 1);
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn join_invalid_kind_returns_null() {
            let (left, right, series) = make_left_right();
            let lk = cstr("k");
            let rk = cstr("k");
            let lon: [*const c_char; 1] = [lk.as_ptr()];
            let ron: [*const c_char; 1] = [rk.as_ptr()];
            // 99 isn't a CompatJoinKind variant.
            let out = dataframe_join(
                left,
                right,
                lon.as_ptr(),
                lon.len(),
                ron.as_ptr(),
                ron.len(),
                99,
            );
            assert!(out.is_null());
            cleanup(left, right, series);
        }

        #[test]
        fn join_null_inputs_return_null() {
            let (left, right, series) = make_left_right();
            assert!(join_on_k(ptr::null_mut(), right,
                              CompatJoinKind::Inner).is_null());
            assert!(join_on_k(left, ptr::null_mut(),
                              CompatJoinKind::Inner).is_null());
            cleanup(left, right, series);
        }

        #[test]
        fn join_empty_on_arrays_return_null_for_non_cross() {
            // Inner / left / outer / semi / anti require at least one key.
            let (left, right, series) = make_left_right();
            let out = dataframe_join(
                left,
                right,
                ptr::null(),
                0,
                ptr::null(),
                0,
                CompatJoinKind::Inner as i32,
            );
            assert!(out.is_null());
            cleanup(left, right, series);
        }
    }

    /// `dataframe_join_asof` and the option-rich `*_options` variant.
    mod dataframe_join_asof_tests {
        use super::*;
        use super::test_util::*;

        /// Quotes (left) and trades (right). Each side is sorted by the
        /// join key — a prerequisite for asof joins.
        fn make_quotes_trades(
        ) -> (*mut DataFrame, *mut DataFrame, [*mut Series; 4]) {
            let lk = make_i64("ts", &[1, 5, 10]);
            let lv = make_i32("quote", &[100, 200, 300]);
            let rk = make_i64("ts", &[2, 6, 11]);
            let rw = make_i32("trade", &[1000, 2000, 3000]);
            let left = make_df(&[lk, lv]);
            let right = make_df(&[rk, rw]);
            (left, right, [lk, lv, rk, rw])
        }

        fn run_asof(
            left: *mut DataFrame,
            right: *mut DataFrame,
            strategy: CompatAsofStrategy,
        ) -> *mut DataFrame {
            let lk = cstr("ts");
            let rk = cstr("ts");
            dataframe_join_asof(
                left, right, lk.as_ptr(), rk.as_ptr(), strategy as i32,
            )
        }

        fn cleanup(
            left: *mut DataFrame,
            right: *mut DataFrame,
            series: [*mut Series; 4],
        ) {
            dataframe_drop(left);
            dataframe_drop(right);
            for s in series {
                series_drop(s);
            }
        }

        #[test]
        fn asof_backward_strategy() {
            let (left, right, series) = make_quotes_trades();
            let out = run_asof(left, right, CompatAsofStrategy::Backward);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), dataframe_height(left));
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn asof_forward_strategy() {
            let (left, right, series) = make_quotes_trades();
            let out = run_asof(left, right, CompatAsofStrategy::Forward);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), dataframe_height(left));
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn asof_nearest_strategy() {
            let (left, right, series) = make_quotes_trades();
            let out = run_asof(left, right, CompatAsofStrategy::Nearest);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), dataframe_height(left));
            dataframe_drop(out);
            cleanup(left, right, series);
        }

        #[test]
        fn asof_invalid_strategy_returns_null() {
            let (left, right, series) = make_quotes_trades();
            let lk = cstr("ts");
            let rk = cstr("ts");
            let out = dataframe_join_asof(
                left, right, lk.as_ptr(), rk.as_ptr(), 999,
            );
            assert!(out.is_null());
            cleanup(left, right, series);
        }

        #[test]
        fn asof_options_with_by_keys() {
            // Same shape but each side carries a `by` partition column.
            let lk = make_i64("ts", &[1, 5, 1, 5]);
            let lby = make_str("g", &["a", "a", "b", "b"]);
            let lv = make_i32("v", &[10, 20, 30, 40]);
            let rk = make_i64("ts", &[2, 6, 2, 6]);
            let rby = make_str("g", &["a", "a", "b", "b"]);
            let rw = make_i32("w", &[100, 200, 300, 400]);
            let left = make_df(&[lk, lby, lv]);
            let right = make_df(&[rk, rby, rw]);

            let ts_l = cstr("ts");
            let ts_r = cstr("ts");
            let g_l = cstr("g");
            let g_r = cstr("g");
            let lby_arr: [*const c_char; 1] = [g_l.as_ptr()];
            let rby_arr: [*const c_char; 1] = [g_r.as_ptr()];
            let out = dataframe_join_asof_options(
                left,
                right,
                ts_l.as_ptr(),
                ts_r.as_ptr(),
                CompatAsofStrategy::Backward as i32,
                lby_arr.as_ptr(),
                lby_arr.len(),
                rby_arr.as_ptr(),
                rby_arr.len(),
                CompatAsofToleranceKind::None as i32,
                0,
                0.0,
            );
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), dataframe_height(left));
            dataframe_drop(out);
            dataframe_drop(left);
            dataframe_drop(right);
            for s in [lk, lby, lv, rk, rby, rw] {
                series_drop(s);
            }
        }

        #[test]
        fn asof_options_with_integer_tolerance() {
            let (left, right, series) = make_quotes_trades();
            let lk = cstr("ts");
            let rk = cstr("ts");
            let out = dataframe_join_asof_options(
                left,
                right,
                lk.as_ptr(),
                rk.as_ptr(),
                CompatAsofStrategy::Backward as i32,
                ptr::null(),
                0,
                ptr::null(),
                0,
                CompatAsofToleranceKind::Integer as i32,
                3,
                0.0,
            );
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), dataframe_height(left));
            dataframe_drop(out);
            cleanup(left, right, series);
        }
    }

    /// vstack appends rows; hstack appends columns.
    mod dataframe_stack {
        use super::*;
        use super::test_util::*;

        #[test]
        fn vstack_appends_rows() {
            let a_x = make_i32("x", &[1, 2]);
            let a_g = make_str("g", &["a", "b"]);
            let a = make_df(&[a_x, a_g]);
            let b_x = make_i32("x", &[3, 4]);
            let b_g = make_str("g", &["c", "d"]);
            let b = make_df(&[b_x, b_g]);
            let out = dataframe_vstack(a, b);
            assert!(!out.is_null());
            assert_eq!(dataframe_height(out), 4);
            assert_eq!(read_i32_col(out, "x"), vec![1, 2, 3, 4]);
            dataframe_drop(out);
            dataframe_drop(a);
            dataframe_drop(b);
            for s in [a_x, a_g, b_x, b_g] {
                series_drop(s);
            }
        }

        #[test]
        fn vstack_schema_mismatch_returns_null() {
            // Different column types between a and b -> polars rejects.
            let a_x = make_i32("x", &[1]);
            let a = make_df(&[a_x]);
            let b_x = make_f64("x", &[1.0]);
            let b = make_df(&[b_x]);
            assert!(dataframe_vstack(a, b).is_null());
            dataframe_drop(a);
            dataframe_drop(b);
            series_drop(a_x);
            series_drop(b_x);
        }

        #[test]
        fn vstack_null_inputs_return_null() {
            let a_x = make_i32("x", &[1]);
            let a = make_df(&[a_x]);
            assert!(dataframe_vstack(ptr::null_mut(), a).is_null());
            assert!(dataframe_vstack(a, ptr::null_mut()).is_null());
            dataframe_drop(a);
            series_drop(a_x);
        }

        #[test]
        fn hstack_appends_columns() {
            let a_x = make_i32("x", &[1, 2, 3]);
            let a = make_df(&[a_x]);
            let extra1 = make_i32("y", &[10, 20, 30]);
            let extra2 = make_str("g", &["a", "b", "c"]);
            let ptrs: [*const Series; 2] =
                [extra1 as *const _, extra2 as *const _];
            let out = dataframe_hstack(a, ptrs.as_ptr(), ptrs.len());
            assert!(!out.is_null());
            assert_eq!(dataframe_width(out), 3);
            assert_eq!(read_column_names(out), vec!["x", "y", "g"]);
            assert_eq!(read_i32_col(out, "y"), vec![10, 20, 30]);
            dataframe_drop(out);
            dataframe_drop(a);
            series_drop(a_x);
            series_drop(extra1);
            series_drop(extra2);
        }

        #[test]
        fn hstack_null_inputs_return_null() {
            assert!(dataframe_hstack(ptr::null_mut(), ptr::null(), 0).is_null());
            let a_x = make_i32("x", &[1]);
            let a = make_df(&[a_x]);
            // null Series in the array
            let ptrs: [*const Series; 1] = [ptr::null()];
            assert!(dataframe_hstack(a, ptrs.as_ptr(), ptrs.len()).is_null());
            dataframe_drop(a);
            series_drop(a_x);
        }
    }

    /// pivot / unpivot reshape operations.
    mod dataframe_reshape {
        use super::*;
        use super::test_util::*;

        /// Long-form table: id ∈ {1,2}, type ∈ {"x","y"}, value ∈ ints.
        fn make_long(
        ) -> (*mut DataFrame, *mut Series, *mut Series, *mut Series) {
            let id = make_i32("id", &[1, 1, 2, 2]);
            let ty = make_str("type", &["x", "y", "x", "y"]);
            let v = make_i32("value", &[10, 11, 20, 21]);
            let df = make_df(&[id, ty, v]);
            (df, id, ty, v)
        }

        #[test]
        fn pivot_with_first_agg() {
            let (df, id, ty, v) = make_long();
            let on = cstr("type");
            let on_arr: [*const c_char; 1] = [on.as_ptr()];
            let idx = cstr("id");
            let idx_arr: [*const c_char; 1] = [idx.as_ptr()];
            let val = cstr("value");
            let val_arr: [*const c_char; 1] = [val.as_ptr()];
            let out = dataframe_pivot(
                df,
                on_arr.as_ptr(),
                on_arr.len(),
                idx_arr.as_ptr(),
                idx_arr.len(),
                val_arr.as_ptr(),
                val_arr.len(),
                CompatPivotAgg::First as i32,
            );
            assert!(!out.is_null());
            // 2 unique ids x (id col + x col + y col) = 2 rows, 3 cols.
            assert_eq!(dataframe_height(out), 2);
            assert_eq!(dataframe_width(out), 3);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(id);
            series_drop(ty);
            series_drop(v);
        }

        #[test]
        fn pivot_unknown_agg_returns_null() {
            let (df, id, ty, v) = make_long();
            let on = cstr("type");
            let on_arr: [*const c_char; 1] = [on.as_ptr()];
            let idx = cstr("id");
            let idx_arr: [*const c_char; 1] = [idx.as_ptr()];
            let val = cstr("value");
            let val_arr: [*const c_char; 1] = [val.as_ptr()];
            let out = dataframe_pivot(
                df,
                on_arr.as_ptr(),
                on_arr.len(),
                idx_arr.as_ptr(),
                idx_arr.len(),
                val_arr.as_ptr(),
                val_arr.len(),
                999,
            );
            assert!(out.is_null());
            dataframe_drop(df);
            series_drop(id);
            series_drop(ty);
            series_drop(v);
        }

        #[test]
        fn unpivot_melts_wide_to_long() {
            // Wide-form: id + a + b.
            let id = make_i32("id", &[1, 2]);
            let a = make_i32("a", &[10, 20]);
            let b = make_i32("b", &[100, 200]);
            let df = make_df(&[id, a, b]);
            let a_n = cstr("a");
            let b_n = cstr("b");
            let on: [*const c_char; 2] = [a_n.as_ptr(), b_n.as_ptr()];
            let id_n = cstr("id");
            let idx: [*const c_char; 1] = [id_n.as_ptr()];
            let out = dataframe_unpivot(
                df,
                on.as_ptr(),
                on.len(),
                idx.as_ptr(),
                idx.len(),
            );
            assert!(!out.is_null());
            // 2 ids * 2 value columns -> 4 rows.
            assert_eq!(dataframe_height(out), 4);
            // Columns: id + "variable" + "value".
            assert_eq!(read_column_names(out),
                       vec!["id", "variable", "value"]);
            dataframe_drop(out);
            dataframe_drop(df);
            series_drop(id);
            series_drop(a);
            series_drop(b);
        }

        #[test]
        fn unpivot_unknown_column_returns_null() {
            let (df, id, ty, v) = make_long();
            let bad = cstr("nope");
            let on: [*const c_char; 1] = [bad.as_ptr()];
            let id_n = cstr("id");
            let idx: [*const c_char; 1] = [id_n.as_ptr()];
            let out = dataframe_unpivot(
                df,
                on.as_ptr(),
                on.len(),
                idx.as_ptr(),
                idx.len(),
            );
            assert!(out.is_null());
            dataframe_drop(df);
            series_drop(id);
            series_drop(ty);
            series_drop(v);
        }
    }

    /// `dataframe_write_*` / `dataframe_read_*` round trips, plus
    /// `dataframe_to_string`.
    mod dataframe_io {
        use super::*;
        use super::test_util::*;

        fn write_round_trip(
            df: *mut DataFrame,
            ext: &str,
            writer: extern "C" fn(*mut DataFrame, *const c_char) -> i32,
            reader: extern "C" fn(*const c_char) -> *mut DataFrame,
        ) -> *mut DataFrame {
            let dir = tempfile::tempdir().expect("tempdir");
            let path = dir.path().join(format!("out.{}", ext));
            let p_owned = cstr(path.to_str().unwrap());
            let rc = writer(df, p_owned.as_ptr());
            assert_eq!(rc, 0, "writer returned non-zero status");
            let back = reader(p_owned.as_ptr());
            assert!(!back.is_null(), "reader returned null");
            back
        }

        // Use i64 input throughout: CSV / JSON-Lines readers infer
        // integer columns as i64, and Parquet preserves the i64 schema —
        // so all three round-trip back to i64 uniformly.

        #[test]
        fn csv_round_trip_preserves_shape_and_values() {
            let xs = make_i64("x", &[1, 2, 3]);
            let gs = make_str("g", &["a", "b", "c"]);
            let df = make_df(&[xs, gs]);
            let back = write_round_trip(
                df,
                "csv",
                dataframe_write_csv,
                dataframe_read_csv,
            );
            assert_eq!(dataframe_height(back), 3);
            assert_eq!(read_column_names(back), vec!["x", "g"]);
            assert_eq!(read_i64_col(back, "x"), vec![1, 2, 3]);
            assert_eq!(read_str_col(back, "g"),
                       vec!["a".to_string(), "b".to_string(), "c".to_string()]);
            dataframe_drop(back);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn parquet_round_trip_preserves_shape_and_values() {
            let xs = make_i64("x", &[1, 2, 3]);
            let gs = make_str("g", &["a", "b", "c"]);
            let df = make_df(&[xs, gs]);
            let back = write_round_trip(
                df,
                "parquet",
                dataframe_write_parquet,
                dataframe_read_parquet,
            );
            assert_eq!(dataframe_height(back), 3);
            assert_eq!(read_i64_col(back, "x"), vec![1, 2, 3]);
            dataframe_drop(back);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn json_lines_round_trip_preserves_shape_and_values() {
            let xs = make_i64("x", &[1, 2, 3]);
            let gs = make_str("g", &["a", "b", "c"]);
            let df = make_df(&[xs, gs]);
            let back = write_round_trip(
                df,
                "jsonl",
                dataframe_write_json_lines,
                dataframe_read_json_lines,
            );
            assert_eq!(dataframe_height(back), 3);
            assert_eq!(read_i64_col(back, "x"), vec![1, 2, 3]);
            dataframe_drop(back);
            dataframe_drop(df);
            series_drop(xs);
            series_drop(gs);
        }

        #[test]
        fn read_csv_missing_path_returns_null() {
            let dir = tempfile::tempdir().expect("tempdir");
            let p = dir.path().join("nope.csv");
            let p_owned = cstr(p.to_str().unwrap());
            assert!(dataframe_read_csv(p_owned.as_ptr()).is_null());
        }

        #[test]
        fn write_csv_status_codes_null_inputs() {
            // write returns 1 for null df / null path, not 0 (success).
            let xs = make_i32("x", &[1]);
            let df = make_df(&[xs]);
            assert_eq!(dataframe_write_csv(ptr::null_mut(),
                                           cstr("/tmp/x").as_ptr()), 1);
            assert_eq!(dataframe_write_csv(df, ptr::null()), 1);
            dataframe_drop(df);
            series_drop(xs);
        }

        #[test]
        fn to_string_returns_non_null_cstring() {
            let xs = make_i32("x", &[1, 2]);
            let df = make_df(&[xs]);
            let s = dataframe_to_string(df);
            assert!(!s.is_null());
            let formatted = take_cstring(s);
            assert!(formatted.contains("x"),
                    "to_string output missing column header: {:?}",
                    formatted);
            dataframe_drop(df);
            series_drop(xs);
        }

        #[test]
        fn to_string_null_df_returns_null() {
            assert!(dataframe_to_string(ptr::null_mut()).is_null());
        }
    }
}
