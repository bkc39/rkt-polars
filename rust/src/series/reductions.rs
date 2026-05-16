use crate::prelude::*;
use crate::*;

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
