//! The reason a call failed, carried out of band.  An entry point that can
//! fail calls `clear_last_error` on entry and records the cause before it
//! returns NULL or a non-zero status.  The Racket wrapper names the operation
//! and the path, so the recorded message is the cause alone.

use crate::prelude::*;
use std::cell::RefCell;

use super::strings::rust_string_to_ptr;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

pub(crate) fn set_last_error(msg: impl Into<String>) {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(msg.into()));
}

pub(crate) fn clear_last_error() {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = None);
}

pub(crate) fn record<T, E: std::fmt::Display>(
    result: Result<T, E>,
) -> Option<T> {
    result.map_err(|err| set_last_error(err.to_string())).ok()
}

pub(crate) fn decode_path<'a>(path: *const c_char) -> Option<&'a str> {
    if path.is_null() {
        set_last_error("path is null");
        return None;
    }
    record(
        unsafe { CStr::from_ptr(path) }
            .to_str()
            .map_err(|err| format!("path is not valid UTF-8: {}", err)),
    )
}

#[no_mangle]
pub extern "C" fn last_error_message() -> *const c_char {
    LAST_ERROR.with(|slot| match slot.borrow().as_deref() {
        Some(msg) => rust_string_to_ptr(msg),
        None => ptr::null(),
    })
}
