use crate::prelude::*;
use crate::*;

macro_rules! series_typed_reductions {
    ($downcast:ident, $compat_opt:ident,
     $sum:ident, $min:ident, $max:ident, $mean:ident) => {
        #[no_mangle]
        pub extern "C" fn $sum(s_ptr: *const Series) -> $compat_opt {
            scalar_result($compat_opt::FAILED, || {
                let s = unsafe { deref_arg(s_ptr, "series") }?;
                Ok($compat_opt::from_option(s.$downcast()?.sum()))
            })
        }

        #[no_mangle]
        pub extern "C" fn $min(s_ptr: *const Series) -> $compat_opt {
            scalar_result($compat_opt::FAILED, || {
                let s = unsafe { deref_arg(s_ptr, "series") }?;
                Ok($compat_opt::from_option(s.$downcast()?.min()))
            })
        }

        #[no_mangle]
        pub extern "C" fn $max(s_ptr: *const Series) -> $compat_opt {
            scalar_result($compat_opt::FAILED, || {
                let s = unsafe { deref_arg(s_ptr, "series") }?;
                Ok($compat_opt::from_option(s.$downcast()?.max()))
            })
        }

        #[no_mangle]
        pub extern "C" fn $mean(s_ptr: *const Series) -> CompatOptF64 {
            scalar_result(CompatOptF64::FAILED, || {
                let s = unsafe { deref_arg(s_ptr, "series") }?;
                Ok(CompatOptF64::from_option(s.$downcast()?.mean()))
            })
        }
    };
}

series_typed_reductions!(
    i8,
    CompatOptI8,
    series_sum_i8_v2,
    series_min_i8_v2,
    series_max_i8_v2,
    series_mean_i8_v2
);
series_typed_reductions!(
    i16,
    CompatOptI16,
    series_sum_i16_v2,
    series_min_i16_v2,
    series_max_i16_v2,
    series_mean_i16_v2
);
series_typed_reductions!(
    i32,
    CompatOptI32,
    series_sum_i32_v2,
    series_min_i32_v2,
    series_max_i32_v2,
    series_mean_i32_v2
);
series_typed_reductions!(
    i64,
    CompatOptI64,
    series_sum_i64_v2,
    series_min_i64_v2,
    series_max_i64_v2,
    series_mean_i64_v2
);
series_typed_reductions!(
    u8,
    CompatOptU8,
    series_sum_u8_v2,
    series_min_u8_v2,
    series_max_u8_v2,
    series_mean_u8_v2
);
series_typed_reductions!(
    u16,
    CompatOptU16,
    series_sum_u16_v2,
    series_min_u16_v2,
    series_max_u16_v2,
    series_mean_u16_v2
);
series_typed_reductions!(
    u32,
    CompatOptU32,
    series_sum_u32_v2,
    series_min_u32_v2,
    series_max_u32_v2,
    series_mean_u32_v2
);
series_typed_reductions!(
    u64,
    CompatOptU64,
    series_sum_u64_v2,
    series_min_u64_v2,
    series_max_u64_v2,
    series_mean_u64_v2
);
series_typed_reductions!(
    f32,
    CompatOptF32,
    series_sum_f32_v2,
    series_min_f32_v2,
    series_max_f32_v2,
    series_mean_f32_v2
);
series_typed_reductions!(
    f64,
    CompatOptF64,
    series_sum_f64_v2,
    series_min_f64_v2,
    series_max_f64_v2,
    series_mean_f64_v2
);

#[no_mangle]
pub extern "C" fn series_n_unique_v2(s_ptr: *const Series) -> i64 {
    scalar_result(-1, || {
        let s = unsafe { deref_arg(s_ptr, "series") }?;
        Ok(s.n_unique()? as i64)
    })
}
