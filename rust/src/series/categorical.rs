use crate::prelude::*;
use crate::*;

pub(crate) fn enum_dtype(categories: StrListArg) -> Option<DataType> {
    let names = record(unsafe { str_list_arg(categories) })?;
    record(FrozenCategories::new(names)).map(DataType::from_frozen_categories)
}

#[no_mangle]
pub extern "C" fn series_cast_enum_v2(
    s_ptr: *const Series,
    categories: StrListArg,
) -> *mut Series {
    clear_last_error();
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        set_last_error("series is null");
        return ptr::null_mut();
    };
    enum_dtype(categories)
        .and_then(|dtype| guard_panic(|| record(s.strict_cast(&dtype))))
        .map_or(ptr::null_mut(), |out| Box::into_raw(Box::new(out)))
}

#[no_mangle]
pub extern "C" fn series_enum_categories(s_ptr: *const Series) -> *mut Series {
    let Some(s) = (unsafe { s_ptr.as_ref() }) else {
        return ptr::null_mut();
    };
    match s.dtype() {
        DataType::Enum(categories, _) => {
            let names = StringChunked::with_chunk(
                s.name().clone(),
                categories.categories().clone(),
            );
            Box::into_raw(Box::new(names.into_series()))
        }
        _ => ptr::null_mut(),
    }
}
