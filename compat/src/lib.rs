use chrono::prelude::*;
use polars::prelude::*;
use std::ffi::*;

#[no_mangle]
pub extern "C" fn add(left: usize, right: usize) -> usize {
    left + right
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        let result = add(2, 2);
        assert_eq!(result, 4);
    }
}

#[no_mangle]
pub extern "C" fn make_data_frame() -> *mut DataFrame {
    let df = df!(
        "integer" => &[1, 2, 3],
        "date" => &[
            NaiveDate::from_ymd_opt(2025, 1, 1)
                .unwrap().and_hms_opt(0, 0, 0).unwrap(),
            NaiveDate::from_ymd_opt(2025, 1, 2)
                .unwrap().and_hms_opt(0, 0, 0).unwrap(),
            NaiveDate::from_ymd_opt(2025, 1, 3)
                .unwrap().and_hms_opt(0, 0, 0).unwrap(),
        ],
        "float" => &[4.0, 5.0, 6.0],
        "string" => &["a", "b", "c"],
    )
    .unwrap();

    Box::into_raw(Box::new(df))
}

#[no_mangle]
pub extern "C" fn dataframe_to_string(df_ptr: *mut DataFrame) -> *mut c_char {
    if df_ptr.is_null() {
        let c_str =
            CString::new("Received null pointer, nothing to print.").unwrap();
        return c_str.into_raw();
    }

    let df = unsafe { &*df_ptr };
    let df_string = format!("{}", df);
    let c_str = CString::new(df_string).unwrap();

    c_str.into_raw()
}
