use crate::prelude::*;
use crate::*;

macro_rules! group_by_agg {
    ($name:ident, $method:ident) => {
        #[no_mangle]
        pub extern "C" fn $name(
            df_ptr: *mut DataFrame,
            by_ptrs: *const *const c_char,
            n_by: usize,
            agg_ptrs: *const *const c_char,
            n_agg: usize,
        ) -> *mut DataFrame {
            if df_ptr.is_null() {
                return ptr::null_mut();
            }
            let by = match unsafe { collect_c_strings(by_ptrs, n_by) } {
                Some(v) => v,
                None => return ptr::null_mut(),
            };
            let agg = match unsafe { collect_c_strings(agg_ptrs, n_agg) } {
                Some(v) => v,
                None => return ptr::null_mut(),
            };
            let df = unsafe { &*df_ptr };
            let gb = match df.group_by(&by) {
                Ok(gb) => gb,
                Err(_) => return ptr::null_mut(),
            };
            #[allow(deprecated)]
            let result = gb.select(&agg).$method();
            match result {
                Ok(out) => Box::into_raw(Box::new(out)),
                Err(_) => ptr::null_mut(),
            }
        }
    };
}

group_by_agg!(dataframe_group_by_sum, sum);
group_by_agg!(dataframe_group_by_mean, mean);
group_by_agg!(dataframe_group_by_min, min);
group_by_agg!(dataframe_group_by_max, max);
group_by_agg!(dataframe_group_by_count, count);
