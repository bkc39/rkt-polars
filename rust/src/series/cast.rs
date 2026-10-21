use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn series_cast(
    s_ptr: *mut Series,
    target: CompatDType,
) -> *mut Series {
    clear_last_error();
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return ptr::null_mut();
    };
    let Some(dt) = polars_dtype_from_compat(&target) else {
        set_last_error("unsupported cast target");
        return ptr::null_mut();
    };
    guard_panic(|| record(s.cast(&dt)))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
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
        0 => QuantileMethod::Nearest,
        1 => QuantileMethod::Linear,
        2 => QuantileMethod::Lower,
        3 => QuantileMethod::Higher,
        4 => QuantileMethod::Midpoint,
        _ => QuantileMethod::Nearest,
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
