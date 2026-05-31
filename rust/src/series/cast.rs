use crate::prelude::*;
use crate::*;

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

// Quantile of a series, computed in f64 (cast first so every numeric dtype is
// supported uniformly).  `interpol` selects the interpolation strategy; the
// Racket side defaults to Nearest, which is what `describe` uses.  Returns NONE
// for an empty/all-null series or a non-numeric dtype.
#[no_mangle]
pub extern "C" fn series_quantile(
    s_ptr: *mut Series,
    quantile: f64,
    interpol: u8,
) -> CompatOptF64 {
    if s_ptr.is_null() {
        return CompatOptF64::NONE;
    }
    let interpol = match interpol {
        0 => QuantileInterpolOptions::Nearest,
        1 => QuantileInterpolOptions::Linear,
        2 => QuantileInterpolOptions::Lower,
        3 => QuantileInterpolOptions::Higher,
        4 => QuantileInterpolOptions::Midpoint,
        _ => QuantileInterpolOptions::Nearest,
    };
    let s = unsafe { &*s_ptr };
    let casted = match s.cast(&DataType::Float64) {
        Ok(c) => c,
        Err(_) => return CompatOptF64::NONE,
    };
    let ca = match casted.f64() {
        Ok(ca) => ca,
        Err(_) => return CompatOptF64::NONE,
    };
    match ca.quantile(quantile, interpol) {
        Ok(opt) => CompatOptF64::from_option(opt),
        Err(_) => CompatOptF64::NONE,
    }
}
