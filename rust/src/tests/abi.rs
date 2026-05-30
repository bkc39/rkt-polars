use super::*;

fn round_trip_simple(tag: CompatDTypeTag, expect: DataType) {
    let c = CompatDType {
        tag: tag as i32,
        time_unit: CompatTimeUnit::None as i32,
        flags: 0,
        array_width: 0,
    };
    let dt = polars_dtype_from_compat(&c).expect("simple dtype must lift");
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
        let dt = polars_dtype_from_compat(&c).expect("datetime must lift");
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
        let dt = polars_dtype_from_compat(&c).expect("duration must lift");
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
    let ndt = ymdhms_to_naive_datetime(&y).expect("valid YMDHMS converts");
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
