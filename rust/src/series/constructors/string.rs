use crate::prelude::*;
use crate::{clear_last_error, guard_panic, slice_or_empty};

pub(crate) fn name_from_ptr(p: *const c_char) -> PlSmallStr {
    if p.is_null() {
        return PlSmallStr::EMPTY;
    }
    unsafe { CStr::from_ptr(p).to_str() }
        .unwrap_or_default()
        .into()
}

/// Row `i` is `buf[offsets[i]..offsets[i + 1]]`, null where `valid` (NULL
/// when no row is null) holds 0; a NULL or non-UTF-8 `name` is empty.
///
/// Zero rows (`offsets_len == 1`) is an empty String series.
///
/// Returns NULL, recording no reason, when:
/// - `offsets` is NULL or `offsets_len` is 0;
/// - `buf` is NULL with `buf_len > 0`;
/// - `valid` is not NULL and holds fewer than `offsets_len - 1` bytes;
/// - `buf` is not UTF-8;
/// - an offset is negative, below the one before it, past `buf_len`, or
///   inside a character.
///
/// A polars panic also returns NULL, and records `polars panicked: <cause>`.
#[no_mangle]
pub extern "C" fn series_new_str_packed(
    name: *const c_char,
    buf: *const u8,
    buf_len: usize,
    offsets: *const i64,
    offsets_len: usize,
    valid: *const u8,
    valid_len: usize,
) -> *mut Series {
    clear_last_error();
    let rows = offsets_len.saturating_sub(1);
    if offsets_len == 0 || !(valid.is_null() || rows <= valid_len) {
        return ptr::null_mut();
    }
    let Some(bytes) = (unsafe { slice_or_empty(buf, buf_len) }) else {
        return ptr::null_mut();
    };
    let Some(offsets) = (unsafe { slice_or_empty(offsets, offsets_len) })
    else {
        return ptr::null_mut();
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    let Ok(start) = usize::try_from(offsets[0]) else {
        return ptr::null_mut();
    };
    if !text.is_char_boundary(start) {
        return ptr::null_mut();
    }
    let valid = unsafe { slice_or_empty(valid, rows) };
    guard_panic(|| {
        let mut builder = StringChunkedBuilder::new(name_from_ptr(name), rows);
        for (row, bounds) in offsets.windows(2).enumerate() {
            let start = usize::try_from(bounds[0]).ok()?;
            let end = usize::try_from(bounds[1]).ok()?;
            let value = text.get(start..end)?;
            if valid.is_some_and(|valid| valid[row] == 0) {
                builder.append_null();
            } else {
                builder.append_value(value);
            }
        }
        Some(builder.finish().into_series())
    })
    .map_or(ptr::null_mut(), |series| Box::into_raw(Box::new(series)))
}
