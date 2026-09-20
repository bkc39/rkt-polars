//! Carrying a failure reason across the FFI boundary.
//!
//! The C ABI can only hand back a status code or a null pointer, so the reason
//! a call failed has to travel out of band.  Each entry point that can fail
//! clears this slot on the way in and records a message on the way out; the
//! caller, having seen a non-zero status or a null result, reads the message
//! with `last_error_message`.
//!
//! The slot is thread-local.  Racket runs foreign calls on the thread that
//! made them, so a message is always read back on the thread that recorded it,
//! and two Racket places cannot overwrite each other's failure.

use crate::prelude::*;
use std::cell::RefCell;

use super::strings::rust_string_to_ptr;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

/// Record `msg` as this thread's most recent failure.
pub(crate) fn set_last_error(msg: impl Into<String>) {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = Some(msg.into()));
}

/// Forget any recorded failure.
///
/// Entry points call this on the way in, so a caller can never attribute a
/// message left behind by an earlier, unrelated failure to the call it just
/// made.
pub(crate) fn clear_last_error() {
    LAST_ERROR.with(|slot| *slot.borrow_mut() = None);
}

/// Record the reason a `Result` failed, converting it to an `Option`.
///
/// `context` names the operation, so the message reads as
/// `"write parquet: <polars error>"` rather than bare polars text.
pub(crate) fn record<T, E: std::fmt::Display>(
    context: &str,
    result: Result<T, E>,
) -> Option<T> {
    match result {
        Ok(value) => Some(value),
        Err(err) => {
            set_last_error(format!("{}: {}", context, err));
            None
        }
    }
}

/// This thread's most recent failure message, or NULL if there is none.
///
/// The string is freshly allocated and owned by the caller, who releases it
/// with `string_drop` — the same contract as every other string this library
/// returns.
#[no_mangle]
pub extern "C" fn last_error_message() -> *const c_char {
    LAST_ERROR.with(|slot| match slot.borrow().as_deref() {
        Some(msg) => rust_string_to_ptr(msg),
        None => ptr::null(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn take_message() -> Option<String> {
        let ptr = last_error_message();
        if ptr.is_null() {
            return None;
        }
        let owned = unsafe { CStr::from_ptr(ptr) }
            .to_str()
            .expect("utf-8")
            .to_string();
        crate::ffi::string_drop(ptr as *mut c_char);
        Some(owned)
    }

    #[test]
    fn absent_until_something_fails() {
        clear_last_error();
        assert_eq!(take_message(), None);
    }

    #[test]
    fn records_and_clears() {
        clear_last_error();
        set_last_error("boom");
        assert_eq!(take_message().as_deref(), Some("boom"));
        clear_last_error();
        assert_eq!(take_message(), None);
    }

    #[test]
    fn record_prefixes_with_context() {
        clear_last_error();
        let failed: Result<(), std::io::Error> = Err(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "no such file",
        ));
        assert!(record("read csv", failed).is_none());
        assert_eq!(take_message().as_deref(), Some("read csv: no such file"));
    }

    #[test]
    fn record_leaves_success_untouched() {
        clear_last_error();
        let ok: Result<i32, std::io::Error> = Ok(7);
        assert_eq!(record("read csv", ok), Some(7));
        assert_eq!(take_message(), None);
    }

    #[test]
    fn message_survives_being_read_twice() {
        clear_last_error();
        set_last_error("kept");
        assert_eq!(take_message().as_deref(), Some("kept"));
        assert_eq!(take_message().as_deref(), Some("kept"));
    }
}
