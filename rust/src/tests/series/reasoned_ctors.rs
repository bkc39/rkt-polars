use super::test_util::*;
use super::*;

fn same_series(v2: *mut Series, v1: *mut Series) {
    let (v2, v1) = (take_box(v2).expect("a v2 series"), take_box(v1).unwrap());
    assert_eq!(v2.name().as_str(), "");
    assert!(v2.equals_missing(&v1), "{:?} against {:?}", v2, v1);
    assert_eq!(v2.dtype(), v1.dtype());
}

fn refused_with(s: *mut Series, reason: &str) {
    assert!(s.is_null());
    assert_eq!(recorded_error().as_deref(), Some(reason));
}

macro_rules! primitive_v2_rows {
    ($($v2:ident $opt_v2:ident $v1:ident $opt_v1:ident [$($x:expr),+]),+ $(,)?) => {
        $({
            let values = [$($x),+];
            let valid = [1u8, 0, 1];
            let empty = cstr("");
            set_last_error("stale");
            same_series(
                $v2(values.as_ptr(), values.len()),
                $v1(empty.as_ptr(), values.as_ptr(), values.len()),
            );
            assert_eq!(recorded_error(), None, stringify!($v2));
            same_series(
                $opt_v2(values.as_ptr(), valid.as_ptr(), values.len()),
                $opt_v1(empty.as_ptr(), values.as_ptr(), valid.as_ptr(), values.len()),
            );
            set_last_error("stale");
            refused_with($v2(ptr::null(), 3), "the values are null but 3 rows were given");
            set_last_error("stale");
            refused_with(
                $opt_v2(values.as_ptr(), ptr::null(), 3),
                "the validity flags are null but 3 rows were given",
            );
            refused_with(
                $opt_v2(ptr::null(), valid.as_ptr(), 3),
                "the values are null but 3 rows were given",
            );
            set_last_error("stale");
            let none = take_box($v2(ptr::null(), 0)).expect("an empty series");
            assert_eq!(none.len(), 0);
            assert_eq!(recorded_error(), None);
        })+
    };
}

#[test]
fn the_v2_constructors_build_what_the_old_ones_did_and_record_a_refusal() {
    primitive_v2_rows!(
        series_new_i8_v2 series_new_opt_i8_v2 series_new_i8 series_new_opt_i8 [1i8, 2, 3],
        series_new_i16_v2 series_new_opt_i16_v2 series_new_i16 series_new_opt_i16 [1i16, 2, 3],
        series_new_i32_v2 series_new_opt_i32_v2 series_new_i32 series_new_opt_i32 [1i32, 2, 3],
        series_new_i64_v2 series_new_opt_i64_v2 series_new_i64 series_new_opt_i64 [1i64, 2, 3],
        series_new_u8_v2 series_new_opt_u8_v2 series_new_u8 series_new_opt_u8 [1u8, 2, 3],
        series_new_u16_v2 series_new_opt_u16_v2 series_new_u16 series_new_opt_u16 [1u16, 2, 3],
        series_new_u32_v2 series_new_opt_u32_v2 series_new_u32 series_new_opt_u32 [1u32, 2, 3],
        series_new_u64_v2 series_new_opt_u64_v2 series_new_u64 series_new_opt_u64 [1u64, 2, 3],
        series_new_f32_v2 series_new_opt_f32_v2 series_new_f32 series_new_opt_f32 [1f32, 2.5, 3.0],
        series_new_f64_v2 series_new_opt_f64_v2 series_new_f64 series_new_opt_f64 [1f64, 2.5, 3.0],
        series_new_bool_v2 series_new_opt_bool_v2 series_new_bool series_new_opt_bool [1u8, 0, 2],
    );
}

fn ymdhms(year: i32, month: u32, day: u32) -> YMDHMS {
    YMDHMS {
        year,
        month,
        day,
        hour: 3,
        minute: 4,
        second: 5,
    }
}

#[test]
fn the_v2_datetime_constructors_name_an_invalid_date() {
    let values = [ymdhms(2024, 1, 2), ymdhms(2025, 12, 31), ymdhms(2026, 5, 9)];
    let valid = [1u8, 0, 1];
    let empty = cstr("");
    set_last_error("stale");
    same_series(
        series_new_ymdhms_v2(values.as_ptr(), 3),
        series_new_ymdhms(empty.as_ptr(), values.as_ptr(), 3),
    );
    assert_eq!(recorded_error(), None);
    same_series(
        series_new_opt_ymdhms_v2(values.as_ptr(), valid.as_ptr(), 3),
        series_new_opt_ymdhms(
            empty.as_ptr(),
            values.as_ptr(),
            valid.as_ptr(),
            3,
        ),
    );
    let invalid = [ymdhms(2024, 1, 2), ymdhms(2021, 2, 30)];
    set_last_error("stale");
    refused_with(
        series_new_ymdhms_v2(invalid.as_ptr(), 2),
        "invalid date and time: 2021-02-30 03:04:05",
    );
    set_last_error("stale");
    refused_with(
        series_new_opt_ymdhms_v2(invalid.as_ptr(), [1u8, 1].as_ptr(), 2),
        "invalid date and time: 2021-02-30 03:04:05",
    );
    let skipped = take_box(series_new_opt_ymdhms_v2(
        invalid.as_ptr(),
        [1u8, 0].as_ptr(),
        2,
    ))
    .expect("an invalid value under a null is not read");
    assert_eq!(skipped.null_count(), 1);
}

#[test]
fn the_v2_null_constructor_clears_a_stale_reason() {
    set_last_error("stale");
    let s = take_box(series_new_null_v2(4)).expect("a null series");
    assert_eq!(
        (s.len(), s.null_count(), s.dtype()),
        (4, 4, &DataType::Null)
    );
    assert_eq!(s.name().as_str(), "");
    assert_eq!(recorded_error(), None);
}
