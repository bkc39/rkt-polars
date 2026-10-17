use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn series_new_null(
    name: *const c_char,
    length: usize,
) -> *mut Series {
    if name.is_null() {
        return ptr::null_mut();
    }
    let s = Series::full_null(name_from_ptr(name), length, &DataType::Null);
    Box::into_raw(Box::new(s))
}
