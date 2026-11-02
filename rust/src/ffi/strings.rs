//! `polars/private/resource.rkt` writes and reads the same layout.  Word 0
//! is a result block's length in words, which `str_block_drop` frees by.

use crate::prelude::*;
use std::fmt;
use std::sync::atomic::{AtomicUsize, Ordering};

pub type StrArg = *const u64;
pub type StrListArg = *const u64;
pub type StrOut = *mut u64;
pub type StrListOut = *mut u64;

const WORD: usize = std::mem::size_of::<u64>();

static STR_BLOCK_DROPS: AtomicUsize = AtomicUsize::new(0);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StrError {
    Truncated,
    FirstOffset,
    OutOfOrder,
    PastEnd,
    NotUtf8,
}

impl fmt::Display for StrError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            StrError::Truncated => {
                "a string block is shorter than its header says"
            }
            StrError::FirstOffset => "a string block's first offset is not 0",
            StrError::OutOfOrder => "string offsets are out of order",
            StrError::PastEnd => "a string offset is past the block's bytes",
            StrError::NotUtf8 => "a string is not valid UTF-8",
        })
    }
}

impl From<StrError> for PolarsError {
    fn from(err: StrError) -> Self {
        polars_err!(ComputeError: "{}", err)
    }
}

/// The string a single block holds; NULL is an error naming `what`.
///
/// # Safety
/// As for `str_arg`.
pub(crate) unsafe fn name_arg<'a>(
    p: StrArg,
    what: &str,
) -> PolarsResult<&'a str> {
    unsafe { str_arg(p) }?
        .ok_or_else(|| polars_err!(ComputeError: "{} is null", what))
}

/// # Safety
/// `p` points to at least `i + 1` words.
unsafe fn word(p: *const u64, i: usize) -> u64 {
    ptr::read_unaligned(p.add(i))
}

fn index(value: u64) -> Result<usize, StrError> {
    usize::try_from(value).map_err(|_| StrError::Truncated)
}

/// # Safety
/// `p` points to a block's first word.
unsafe fn block_words(p: *const u64) -> Result<usize, StrError> {
    let words = index(word(p, 0))?;
    if words < 2 {
        return Err(StrError::Truncated);
    }
    words.checked_mul(WORD).ok_or(StrError::Truncated)?;
    Ok(words)
}

/// # Safety
/// `start <= end` and `base` points to at least `end` bytes that outlive `'a`.
unsafe fn utf8<'a>(
    base: *const u8,
    start: usize,
    end: usize,
) -> Result<&'a str, StrError> {
    let bytes = std::slice::from_raw_parts(base.add(start), end - start);
    std::str::from_utf8(bytes).map_err(|_| StrError::NotUtf8)
}

/// The string a single block holds; `None` for NULL.
///
/// # Safety
/// A non-NULL `p` points to as many words as its word 0 says, which outlive
/// `'a`; every other bound is checked.
pub(crate) unsafe fn str_arg<'a>(
    p: StrArg,
) -> Result<Option<&'a str>, StrError> {
    if p.is_null() {
        return Ok(None);
    }
    let words = block_words(p)?;
    let len = index(word(p, 1))?;
    if len > (words - 2) * WORD {
        return Err(StrError::Truncated);
    }
    utf8(p.add(2) as *const u8, 0, len).map(Some)
}

/// The strings a list block holds; empty for NULL.
///
/// # Safety
/// As for `str_arg`.
pub(crate) unsafe fn str_list_arg<'a>(
    p: StrListArg,
) -> Result<Vec<&'a str>, StrError> {
    if p.is_null() {
        return Ok(Vec::new());
    }
    let words = block_words(p)?;
    let count = index(word(p, 1))?;
    let data = count
        .checked_add(3)
        .filter(|header| *header <= words)
        .ok_or(StrError::Truncated)?;
    let room = (words - data) * WORD;
    let offsets = (0..=count)
        .map(|i| index(word(p, 2 + i)).map_err(|_| StrError::PastEnd))
        .collect::<Result<Vec<usize>, StrError>>()?;
    if offsets[0] != 0 {
        return Err(StrError::FirstOffset);
    }
    if offsets.windows(2).any(|pair| pair[1] < pair[0]) {
        return Err(StrError::OutOfOrder);
    }
    if offsets[count] > room {
        return Err(StrError::PastEnd);
    }
    let base = p.add(data) as *const u8;
    offsets
        .windows(2)
        .map(|pair| utf8(base, pair[0], pair[1]))
        .collect()
}

fn padded_words(bytes: usize) -> usize {
    bytes.div_ceil(WORD)
}

fn into_block(mut block: Vec<u64>, bytes: &[u8], at: usize) -> *mut u64 {
    block[0] = block.len() as u64;
    let tail = unsafe {
        std::slice::from_raw_parts_mut(
            block.as_mut_ptr().add(at) as *mut u8,
            (block.len() - at) * WORD,
        )
    };
    tail[..bytes.len()].copy_from_slice(bytes);
    Box::into_raw(block.into_boxed_slice()) as *mut u64
}

/// A single block holding `value`, for the caller to free with
/// `str_block_drop`.
pub(crate) fn str_out(value: &str) -> StrOut {
    let bytes = value.as_bytes();
    let mut block = vec![0u64; 2 + padded_words(bytes.len())];
    block[1] = bytes.len() as u64;
    into_block(block, bytes, 2)
}

/// A list block holding `values`, for the caller to free with
/// `str_block_drop`.
pub(crate) fn str_list_out<S: AsRef<str>>(
    values: impl IntoIterator<Item = S>,
) -> StrListOut {
    let mut bytes = Vec::new();
    let mut offsets = vec![0u64];
    for value in values {
        bytes.extend_from_slice(value.as_ref().as_bytes());
        offsets.push(bytes.len() as u64);
    }
    let count = offsets.len() - 1;
    let data = 3 + count;
    let mut block = vec![0u64; data + padded_words(bytes.len())];
    block[1] = count as u64;
    block[2..data].copy_from_slice(&offsets);
    into_block(block, &bytes, data)
}

#[no_mangle]
pub extern "C" fn str_block_drop(p: StrOut) {
    if !p.is_null() {
        let words = unsafe { word(p, 0) } as usize;
        unsafe { drop(Box::from_raw(ptr::slice_from_raw_parts_mut(p, words))) };
        STR_BLOCK_DROPS.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub extern "C" fn str_block_drop_count() -> usize {
    STR_BLOCK_DROPS.load(Ordering::Relaxed)
}

#[no_mangle]
pub extern "C" fn string_drop(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)) };
    }
}
