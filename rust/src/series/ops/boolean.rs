use crate::prelude::*;

macro_rules! bool_binop {
    ($name:ident, $op:tt) => {
        #[no_mangle]
        pub extern "C" fn $name(a_ptr: *mut Series, b_ptr: *mut Series) -> *mut Series {
            if a_ptr.is_null() || b_ptr.is_null() {
                return ptr::null_mut();
            }
            let a = unsafe { &*a_ptr };
            let b = unsafe { &*b_ptr };
            let (a_ca, b_ca) = match (a.bool(), b.bool()) {
                (Ok(x), Ok(y)) => (x, y),
                _ => return ptr::null_mut(),
            };
            let result = a_ca $op b_ca;
            Box::into_raw(Box::new(result.into_series()))
        }
    };
}

bool_binop!(series_and, &);
bool_binop!(series_or, |);
bool_binop!(series_xor, ^);

#[no_mangle]
pub extern "C" fn series_not(s_ptr: *mut Series) -> *mut Series {
    if s_ptr.is_null() {
        return ptr::null_mut();
    }
    let s = unsafe { &*s_ptr };
    match s.bool() {
        Ok(ca) => Box::into_raw(Box::new((!ca).into_series())),
        Err(_) => ptr::null_mut(),
    }
}
