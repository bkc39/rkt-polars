use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn dataframe_select_v2(
    df_ptr: *const DataFrame,
    names: StrListArg,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        df.select(unsafe { str_list_arg(names) }?)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_drop_columns_v2(
    df_ptr: *const DataFrame,
    names: StrListArg,
) -> *mut DataFrame {
    boxed_result(|| {
        let mut out = unsafe { deref_arg(df_ptr, "dataframe") }?.clone();
        for name in unsafe { str_list_arg(names) }? {
            out.drop_in_place(name)?;
        }
        Ok(out)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_rename_v2(
    df_ptr: *const DataFrame,
    old: StrArg,
    new: StrArg,
) -> *mut DataFrame {
    boxed_result(|| {
        let mut out = unsafe { deref_arg(df_ptr, "dataframe") }?.clone();
        let old = unsafe { name_arg(old, "the old name") }?;
        let new = unsafe { name_arg(new, "the new name") }?;
        out.rename(old, new.into())?;
        Ok(out)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_with_column(
    df_ptr: *mut DataFrame,
    series_ptr: *const Series,
) -> *mut DataFrame {
    boxed_result(|| {
        let mut out = unsafe { deref_arg(df_ptr, "dataframe") }?.clone();
        let s = unsafe { deref_arg(series_ptr, "series") }?;
        out.with_column(s.clone().into_column())?;
        Ok(out)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_column_name_v2(
    df_ptr: *const DataFrame,
    index: usize,
) -> StrOut {
    unsafe { df_ptr.as_ref() }
        .and_then(|df| df.get_column_names().get(index).copied())
        .map_or(ptr::null_mut(), |name| str_out(name))
}

#[no_mangle]
pub extern "C" fn dataframe_column_names(
    df_ptr: *const DataFrame,
) -> StrListOut {
    unsafe { df_ptr.as_ref() }
        .map_or(ptr::null_mut(), |df| str_list_out(df.get_column_names()))
}

#[no_mangle]
pub extern "C" fn dataframe_column_v2(
    df_ptr: *const DataFrame,
    name: StrArg,
) -> *mut Series {
    boxed_unguarded(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        let column = df.column(unsafe { name_arg(name, "the name") }?)?;
        Ok(column.as_materialized_series().clone())
    })
}
