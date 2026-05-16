use crate::prelude::*;

pub extern "C" fn string_drop(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}

pub(crate) fn rust_string_to_ptr(value: impl AsRef<str>) -> *const c_char {
    CString::new(value.as_ref())
        .map(CString::into_raw)
        .map(|ptr| ptr as *const c_char)
        .unwrap_or(ptr::null())
}
