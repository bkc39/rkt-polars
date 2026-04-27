use chrono::{NaiveDate, NaiveDateTime};
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
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct CompatOptF64 {
    pub valid: i32,
    pub value: f64,
}

impl CompatOptI32 {
    const NONE: Self = Self { valid: 0, value: 0 };
    fn some(v: i32) -> Self { Self { valid: 1, value: v } }
    fn from_option(o: Option<i32>) -> Self {
        match o { Some(v) => Self::some(v), None => Self::NONE }
    }
}

impl CompatOptF64 {
    const NONE: Self = Self { valid: 0, value: 0.0 };
    fn some(v: f64) -> Self { Self { valid: 1, value: v } }
    fn from_option(o: Option<f64>) -> Self {
        match o { Some(v) => Self::some(v), None => Self::NONE }
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
        #[cfg(feature = "dtype-categorical")]
        DataType::Categorical(_, _) => CompatDType {
            tag: Tag::Categorical as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        #[cfg(feature = "dtype-categorical")]
        DataType::Enum(_, _) => CompatDType {
            tag: Tag::Enum as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        #[cfg(feature = "dtype-decimal")]
        DataType::Decimal(_, _) => CompatDType {
            tag: Tag::Decimal as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        #[cfg(feature = "object")]
        DataType::Object(_, _) => CompatDType {
            tag: Tag::Object as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
        #[cfg(feature = "dtype-struct")]
        DataType::Struct(_) => CompatDType {
            tag: Tag::Struct as i32,
            time_unit: CompatTimeUnit::None as i32,
            flags: 0,
            array_width: 0,
        },
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
        slice
            .iter()
            .map(|&p| unsafe { (&*p).clone() })
            .collect()
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

#[no_mangle]
pub extern "C" fn series_gt_i32(s_ptr: *mut Series, threshold: i32) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    match s.i32() {
        Ok(ca) => {
            let mask = ca.gt(threshold);
            Box::into_raw(Box::new(mask.into_series()))
        }
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
    let opts = SortMultipleOptions::new().with_order_descending_multi(descending);
    let df = unsafe { &*df_ptr };
    match df.sort(names, opts) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_group_by_sum(
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
    let result = gb.select(&agg).sum();
    match result {
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

#[no_mangle]
pub extern "C" fn series_new_i32(
    name: *const c_char,
    data: *const i32,
    length: usize,
) -> *mut Series {
    series_new::<Int32Type>(name, data, length)
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
pub extern "C" fn series_new_i64(
    name: *const c_char,
    data: *const i64,
    length: usize,
) -> *mut Series {
    series_new::<Int64Type>(name, data, length)
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

#[repr(C)]
pub struct YMDHMS {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub second: u32,
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
