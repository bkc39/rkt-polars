use super::*;

/// Build an owning `CString` from a Rust `&str`. The caller holds
/// the `CString` for as long as the FFI call needs the pointer.
pub(super) fn cstr(s: &str) -> CString {
    CString::new(s).expect("test cstring must not contain a nul byte")
}

/// Materialize a `*const c_char` that an FFI extern returned into
/// an owned `String`, freeing the underlying CString.
pub(super) fn take_cstring(p: *const c_char) -> String {
    assert!(!p.is_null(), "expected a non-null CString pointer");
    let s = unsafe { CStr::from_ptr(p) }
        .to_str()
        .expect("FFI string must be valid UTF-8")
        .to_owned();
    unsafe { drop(CString::from_raw(p as *mut c_char)) };
    s
}

fn words(bytes: &[u8]) -> Vec<u64> {
    bytes
        .chunks(8)
        .map(|chunk| {
            let mut word = [0u8; 8];
            word[..chunk.len()].copy_from_slice(chunk);
            u64::from_ne_bytes(word)
        })
        .collect()
}

/// A single argument block holding `value`, as Racket's `_str` builds it.
pub(super) fn str_block(value: &str) -> Vec<u64> {
    let data = words(value.as_bytes());
    let mut block = vec![(2 + data.len()) as u64, value.len() as u64];
    block.extend(data);
    block
}

/// A list argument block holding `values`, as Racket's `_str-list` builds
/// it.
pub(super) fn str_list_block(values: &[&str]) -> Vec<u64> {
    let mut offsets = vec![0u64];
    for value in values {
        offsets.push(offsets[offsets.len() - 1] + value.len() as u64);
    }
    let data = words(values.concat().as_bytes());
    let mut block =
        vec![(2 + offsets.len() + data.len()) as u64, values.len() as u64];
    block.extend(offsets);
    block.extend(data);
    block
}

/// The string a result block holds, the block freed.
pub(super) fn take_str(p: StrOut) -> String {
    assert!(!p.is_null(), "expected a non-null string block");
    let s = unsafe { str_arg(p) }
        .expect("a well-formed string block")
        .expect("a string")
        .to_owned();
    str_block_drop(p);
    s
}

/// The strings a result list block holds, the block freed.
pub(super) fn take_strs(p: StrListOut) -> Vec<String> {
    assert!(!p.is_null(), "expected a non-null string list block");
    let strings = unsafe { str_list_arg(p) }
        .expect("a well-formed string list block")
        .into_iter()
        .map(str::to_owned)
        .collect();
    str_block_drop(p);
    strings
}

/// The reason the last participating call recorded, freed; `None` if it
/// recorded none.
pub(super) fn recorded_error() -> Option<String> {
    let p = last_error_message_v2();
    (!p.is_null()).then(|| take_str(p))
}

pub(super) fn make_i32(name: &str, values: &[i32]) -> *mut Series {
    let n = cstr(name);
    let s = series_new_i32(n.as_ptr(), values.as_ptr(), values.len());
    assert!(!s.is_null(), "series_new_i32 returned null for {:?}", name);
    s
}

pub(super) fn make_f64(name: &str, values: &[f64]) -> *mut Series {
    let n = cstr(name);
    let s = series_new_f64(n.as_ptr(), values.as_ptr(), values.len());
    assert!(!s.is_null());
    s
}

pub(super) fn make_bool(name: &str, values: &[u8]) -> *mut Series {
    let n = cstr(name);
    let s = series_new_bool(n.as_ptr(), values.as_ptr(), values.len());
    assert!(!s.is_null());
    s
}

/// Pack `values` as the Racket side does for `series_new_str_packed`: the
/// UTF-8 back to back, one more offset than rows, one validity byte per row.
pub(super) fn pack_strs(
    values: &[Option<&str>],
) -> (Vec<u8>, Vec<i64>, Vec<u8>) {
    let mut buf = Vec::new();
    let mut offsets = vec![0i64];
    let mut valid = Vec::with_capacity(values.len());
    for value in values {
        buf.extend_from_slice(value.unwrap_or_default().as_bytes());
        offsets.push(buf.len() as i64);
        valid.push(value.is_some() as u8);
    }
    (buf, offsets, valid)
}

pub(super) fn make_opt_str(name: &str, values: &[Option<&str>]) -> *mut Series {
    let (buf, offsets, valid) = pack_strs(values);
    let n = cstr(name);
    let s = series_new_str_packed(
        n.as_ptr(),
        buf.as_ptr(),
        buf.len(),
        offsets.as_ptr(),
        offsets.len(),
        valid.as_ptr(),
        valid.len(),
    );
    assert!(!s.is_null(), "series_new_str_packed returned null");
    s
}

pub(super) fn make_str(name: &str, values: &[&str]) -> *mut Series {
    let values: Vec<Option<&str>> = values.iter().copied().map(Some).collect();
    make_opt_str(name, &values)
}

pub(super) fn make_i64(name: &str, values: &[i64]) -> *mut Series {
    let n = cstr(name);
    let s = series_new_i64(n.as_ptr(), values.as_ptr(), values.len());
    assert!(!s.is_null());
    s
}

/// Build a null-aware primitive series from `Option<T>` values
/// the same way `series_new_opt_*` is used from Racket.
pub(super) fn make_opt_i32(name: &str, values: &[Option<i32>]) -> *mut Series {
    let data: Vec<i32> = values.iter().map(|o| o.unwrap_or(0)).collect();
    let valid: Vec<u8> = values
        .iter()
        .map(|o| if o.is_some() { 1 } else { 0 })
        .collect();
    let n = cstr(name);
    let s = series_new_opt_i32(
        n.as_ptr(),
        data.as_ptr(),
        valid.as_ptr(),
        data.len(),
    );
    assert!(!s.is_null());
    s
}

/// Build a DataFrame from a slice of already-owned Series
/// pointers. The caller still owns each input Series and is
/// responsible for dropping them — `dataframe_new` clones them.
pub(super) fn make_df(columns: &[*mut Series]) -> *mut DataFrame {
    let ptrs: Vec<*const Series> =
        columns.iter().map(|p| *p as *const Series).collect();
    let df = dataframe_new(ptrs.as_ptr(), ptrs.len());
    assert!(!df.is_null(), "dataframe_new returned null");
    df
}

/// Read every column name back through the FFI.
pub(super) fn read_column_names(df: *mut DataFrame) -> Vec<String> {
    take_strs(dataframe_column_names(df))
}

/// Pull a string column out by name and materialize it as a
/// `Vec<String>`. Each element is freed via `take_cstring`.
pub(super) fn read_str_col(df: *mut DataFrame, name: &str) -> Vec<String> {
    let n = str_block(name);
    let s = dataframe_column_v2(df, n.as_ptr());
    assert!(!s.is_null(), "dataframe_column({:?}) returned null", name,);
    let out: Vec<String> = (0..series_len(s))
        .map(|i| {
            let p = series_ref_str(s, i);
            assert!(!p.is_null(), "unexpected null at {}/{}", name, i);
            take_cstring(p)
        })
        .collect();
    series_drop(s);
    out
}

/// Pull an i64 column out by name and materialize it as a Vec.
/// CSV / JSON-Lines readers infer integer columns as i64, so
/// round-trip tests need to read with this variant.
pub(super) fn read_i64_col(df: *mut DataFrame, name: &str) -> Vec<i64> {
    let n = str_block(name);
    let s = dataframe_column_v2(df, n.as_ptr());
    assert!(!s.is_null(), "dataframe_column({:?}) returned null", name,);
    let out: Vec<i64> = (0..series_len(s))
        .map(|i| {
            let v = series_ref_i64(s, i);
            assert_eq!(v.valid, 1, "unexpected null at {}/{}", name, i);
            v.value
        })
        .collect();
    series_drop(s);
    out
}

/// Pull an i32 column out by name and materialize it as a Vec.
pub(super) fn read_i32_col(df: *mut DataFrame, name: &str) -> Vec<i32> {
    let n = str_block(name);
    let s = dataframe_column_v2(df, n.as_ptr());
    assert!(!s.is_null(), "dataframe_column({:?}) returned null", name,);
    let out: Vec<i32> = (0..series_len(s))
        .map(|i| {
            let v = series_ref_i32(s, i);
            assert_eq!(v.valid, 1, "unexpected null at {}/{}", name, i);
            v.value
        })
        .collect();
    series_drop(s);
    out
}

pub(super) fn make_opt_bool(
    name: &str,
    values: &[Option<bool>],
) -> *mut Series {
    let data: Vec<u8> =
        values.iter().map(|o| o.unwrap_or(false) as u8).collect();
    let valid: Vec<u8> = values.iter().map(|o| o.is_some() as u8).collect();
    let n = cstr(name);
    let s = series_new_opt_bool(
        n.as_ptr(),
        data.as_ptr(),
        valid.as_ptr(),
        data.len(),
    );
    assert!(!s.is_null());
    s
}

pub(super) fn opt_bools(s: *mut Series) -> Vec<Option<bool>> {
    (0..series_len(s))
        .map(|i| {
            let v = series_ref_bool(s, i);
            (v.valid == 1).then_some(v.value != 0)
        })
        .collect()
}

pub(super) fn opt_i32s(s: *mut Series) -> Vec<Option<i32>> {
    (0..series_len(s))
        .map(|i| {
            let v = series_ref_i32(s, i);
            (v.valid == 1).then_some(v.value)
        })
        .collect()
}

pub(super) fn read_opt_bool_col(
    df: *mut DataFrame,
    name: &str,
) -> Vec<Option<bool>> {
    let n = str_block(name);
    let s = dataframe_column_v2(df, n.as_ptr());
    assert!(!s.is_null(), "dataframe_column({:?}) returned null", name);
    let out = opt_bools(s);
    series_drop(s);
    out
}

pub(super) fn read_opt_i32_col(
    df: *mut DataFrame,
    name: &str,
) -> Vec<Option<i32>> {
    let n = str_block(name);
    let s = dataframe_column_v2(df, n.as_ptr());
    assert!(!s.is_null(), "dataframe_column({:?}) returned null", name);
    let out = opt_i32s(s);
    series_drop(s);
    out
}

pub(super) fn make_opt_f64(name: &str, values: &[Option<f64>]) -> *mut Series {
    let data: Vec<f64> = values.iter().map(|o| o.unwrap_or(0.0)).collect();
    let valid: Vec<u8> = values
        .iter()
        .map(|o| if o.is_some() { 1 } else { 0 })
        .collect();
    let n = cstr(name);
    let s = series_new_opt_f64(
        n.as_ptr(),
        data.as_ptr(),
        valid.as_ptr(),
        data.len(),
    );
    assert!(!s.is_null());
    s
}

/// Assert that `series_dtype` reports the given tag and time-unit.
pub(super) fn assert_dtype(
    series: *mut Series,
    tag: CompatDTypeTag,
    time_unit: CompatTimeUnit,
) {
    let dt = series_dtype(series);
    assert_eq!(dt.tag, tag as i32, "dtype tag mismatch");
    assert_eq!(dt.time_unit, time_unit as i32, "dtype time_unit mismatch",);
}

pub(super) fn scratch_dir() -> tempfile::TempDir {
    tempfile::tempdir().expect("tempdir")
}

/// The names in `dir`, sorted.
pub(super) fn entries(dir: &std::path::Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    names
}
