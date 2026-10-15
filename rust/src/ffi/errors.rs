//! The reason a call failed, carried out of band.  An entry point that can
//! fail calls `clear_last_error` on entry and records the cause before it
//! returns NULL or a non-zero status.  The Racket wrapper names the operation
//! and the path, so the recorded message is the cause alone.

use crate::prelude::*;
use std::cell::RefCell;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Once;

use super::strings::rust_string_to_ptr;

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

static QUIET_HOOK: Once = Once::new();
static ACTIVE_GUARDS: AtomicUsize = AtomicUsize::new(0);

/// A caught panic is reported as the failure reason, so the panic hook stays
/// silent while any guard is active (polars panics on its pool's threads as
/// well as the caller's) and defers to the previous hook otherwise.
fn install_quiet_hook() {
    QUIET_HOOK.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if ACTIVE_GUARDS.load(Ordering::SeqCst) == 0 {
                previous(info);
            }
        }));
    });
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

/// A panic that unwinds out of an `extern "C"` function aborts the host
/// process, and polars panics on some inputs where it could return an error,
/// so an entry point that runs polars code on caller-controlled data records
/// the panic as the failure reason instead.
pub(crate) fn guard_panic<T>(f: impl FnOnce() -> Option<T>) -> Option<T> {
    install_quiet_hook();
    ACTIVE_GUARDS.fetch_add(1, Ordering::SeqCst);
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(f));
    ACTIVE_GUARDS.fetch_sub(1, Ordering::SeqCst);
    result.unwrap_or_else(|payload| {
        let msg = payload
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| payload.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "unknown cause".to_string());
        set_last_error(format!("polars panicked: {}", msg));
        None
    })
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
