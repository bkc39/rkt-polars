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

pub(super) fn make_str(name: &str, values: &[&str]) -> *mut Series {
    // series_new_str takes an array of `*const c_char`; keep the
    // CStrings alive for the duration of the call.
    let owned: Vec<CString> = values.iter().map(|v| cstr(v)).collect();
    let ptrs: Vec<*const c_char> = owned.iter().map(|c| c.as_ptr()).collect();
    let n = cstr(name);
    let s = series_new_str(n.as_ptr(), ptrs.as_ptr(), ptrs.len());
    assert!(!s.is_null());
    s
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
    (0..dataframe_width(df))
        .map(|i| take_cstring(dataframe_column_name(df, i)))
        .collect()
}

/// Pull a string column out by name and materialize it as a
/// `Vec<String>`. Each element is freed via `take_cstring`.
pub(super) fn read_str_col(df: *mut DataFrame, name: &str) -> Vec<String> {
    let n = cstr(name);
    let s = dataframe_column(df, n.as_ptr());
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
    let n = cstr(name);
    let s = dataframe_column(df, n.as_ptr());
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
    let n = cstr(name);
    let s = dataframe_column(df, n.as_ptr());
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
