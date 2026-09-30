use crate::prelude::*;
use crate::{clear_last_error, guard_panic};

pub(crate) fn name_from_ptr(p: *const c_char) -> PlSmallStr {
    if p.is_null() {
        return PlSmallStr::EMPTY;
    }
    unsafe { CStr::from_ptr(p).to_str() }
        .unwrap_or_default()
        .into()
}

/// Row `i` is `buf[offsets[i]..offsets[i + 1]]`, null where `valid` (NULL
/// when no row is null) holds 0. NULL on zero rows, which keeps an empty list
/// an error in Racket, and on offsets that leave `buf` or split a character;
/// only a polars panic records a reason.
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
    if rows == 0
        || offsets.is_null()
        || (buf.is_null() && buf_len > 0)
        || !(valid.is_null() || rows <= valid_len)
    {
        return ptr::null_mut();
    }
    let bytes = if buf_len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(buf, buf_len) }
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    let offsets = unsafe { std::slice::from_raw_parts(offsets, offsets_len) };
    let valid = (!valid.is_null())
        .then(|| unsafe { std::slice::from_raw_parts(valid, rows) });
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
