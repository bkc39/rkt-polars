use crate::prelude::*;
use crate::{clear_last_error, guard_panic, record, set_last_error};

pub(crate) fn series_bool_result<F>(
    a_ptr: *mut Series,
    b_ptr: *mut Series,
    f: F,
) -> *mut Series
where
    F: FnOnce(&BooleanChunked, &BooleanChunked) -> BooleanChunked,
{
    clear_last_error();
    let (Some(a), Some(b)) =
        (unsafe { a_ptr.as_ref() }, unsafe { b_ptr.as_ref() })
    else {
        set_last_error("series is null");
        return ptr::null_mut();
    };
    guard_panic(|| {
        let (a_ca, b_ca) = (record(a.bool())?, record(b.bool())?);
        if a_ca.len() != b_ca.len() && a_ca.len() != 1 && b_ca.len() != 1 {
            set_last_error(format!(
                "cannot combine series of different lengths: got {} and {}",
                a_ca.len(),
                b_ca.len()
            ));
            return None;
        }
        Some(f(a_ca, b_ca).into_series())
    })
    .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

macro_rules! bool_binop {
    ($name:ident, $op:tt) => {
        #[no_mangle]
        pub extern "C" fn $name(a_ptr: *mut Series, b_ptr: *mut Series) -> *mut Series {
            series_bool_result(a_ptr, b_ptr, |a, b| a $op b)
        }
    };
}

bool_binop!(series_and, &);
bool_binop!(series_or, |);
bool_binop!(series_xor, ^);

#[no_mangle]
pub extern "C" fn series_not(s_ptr: *mut Series) -> *mut Series {
    clear_last_error();
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        set_last_error("series is null");
        return ptr::null_mut();
    };
    guard_panic(|| Some((!record(s.bool())?).into_series()))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}
