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
pub extern "C" fn series_std_v2(
    s_ptr: *const Series,
    ddof: u8,
) -> CompatOptF64 {
    scalar_result(CompatOptF64::FAILED, || {
        let s = unsafe { deref_arg(s_ptr, "series") }?;
        Ok(CompatOptF64::from_option(s.std(ddof)))
    })
}

#[no_mangle]
pub extern "C" fn series_var_v2(
    s_ptr: *const Series,
    ddof: u8,
) -> CompatOptF64 {
    scalar_result(CompatOptF64::FAILED, || {
        let s = unsafe { deref_arg(s_ptr, "series") }?;
        Ok(CompatOptF64::from_option(s.var(ddof)))
    })
}

#[no_mangle]
pub extern "C" fn series_quantile_v2(
    s_ptr: *const Series,
    quantile: f64,
    interpol: u8,
) -> CompatOptF64 {
    scalar_result(CompatOptF64::FAILED, || {
        let s = unsafe { deref_arg(s_ptr, "series") }?;
        let method = match interpol {
            0 => QuantileMethod::Nearest,
            1 => QuantileMethod::Linear,
            2 => QuantileMethod::Lower,
            3 => QuantileMethod::Higher,
            4 => QuantileMethod::Midpoint,
            n => {
                polars_bail!(ComputeError: "unknown quantile method code {}", n)
            }
        };
        let casted = s.cast(&DataType::Float64)?;
        Ok(CompatOptF64::from_option(
            casted.f64()?.quantile(quantile, method)?,
        ))
    })
}
