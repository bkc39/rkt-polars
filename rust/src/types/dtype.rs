use crate::prelude::*;

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

pub(crate) const COMPAT_DTYPE_HAS_TIMEZONE: u32 = 0x1;

pub(crate) fn compat_time_unit_from_polars(
    time_unit: &TimeUnit,
) -> CompatTimeUnit {
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
pub(crate) fn polars_dtype_from_compat(c: &CompatDType) -> Option<DataType> {
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
pub(crate) fn compat_dtype_from_polars(dtype: &DataType) -> CompatDType {
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
