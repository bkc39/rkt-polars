use crate::prelude::*;
use crate::*;

macro_rules! group_by_agg {
    ($name:ident, $method:ident) => {
        #[no_mangle]
        pub extern "C" fn $name(
            df_ptr: *const DataFrame,
            by: StrListArg,
            agg: StrListArg,
        ) -> *mut DataFrame {
            boxed_result(|| {
                let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
                let by = unsafe { str_list_arg(by) }?;
                let agg = unsafe { str_list_arg(agg) }?;
                #[allow(deprecated)]
                df.group_by(by)?.select(agg).$method()
            })
        }
    };
}

group_by_agg!(dataframe_group_by_sum_v2, sum);
group_by_agg!(dataframe_group_by_mean_v2, mean);
group_by_agg!(dataframe_group_by_min_v2, min);
group_by_agg!(dataframe_group_by_max_v2, max);
group_by_agg!(dataframe_group_by_count_v2, count);
