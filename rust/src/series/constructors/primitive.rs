use crate::prelude::*;
use crate::*;

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
