use crate::prelude::*;
use crate::*;

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatPivotAgg {
    None = 0,
    First = 1,
    Sum = 2,
    Min = 3,
    Max = 4,
    Mean = 5,
    Count = 6,
}

pub(crate) fn compat_pivot_agg(code: i32) -> Option<Expr> {
    match code {
        x if x == CompatPivotAgg::None as i32 => Some(element().item(true)),
        x if x == CompatPivotAgg::First as i32 => Some(element().first()),
        x if x == CompatPivotAgg::Sum as i32 => Some(element().sum()),
        x if x == CompatPivotAgg::Min as i32 => Some(element().min()),
        x if x == CompatPivotAgg::Max as i32 => Some(element().max()),
        x if x == CompatPivotAgg::Mean as i32 => Some(element().mean()),
        x if x == CompatPivotAgg::Count as i32 => Some(element().len()),
        _ => None,
    }
}

// The output's `on` columns are sorted by value, as 0.41.3's
// pivot_stable(sort_columns = true) produced them.
fn pivot_eager(
    df: &DataFrame,
    on: Vec<String>,
    index: Vec<String>,
    values: Vec<String>,
    agg: Expr,
) -> PolarsResult<DataFrame> {
    let on_columns = df
        .select(on.iter())?
        .unique_stable(None, UniqueKeepStrategy::First, None)?
        .sort(on.iter(), SortMultipleOptions::default())?;
    let on_sel = cols(on.clone());
    let index_sel = if index.is_empty() {
        all() - on_sel.clone() - cols(values.clone())
    } else {
        cols(index.clone())
    };
    let values_sel = if values.is_empty() {
        all() - on_sel.clone() - index_sel.clone()
    } else {
        cols(values)
    };
    df.clone()
        .lazy()
        .pivot(
            on_sel,
            Arc::new(on_columns),
            index_sel,
            values_sel,
            agg,
            true,
            "_".into(),
            polars::frame::PivotColumnNaming::Auto,
        )
        .collect()
}

fn owned(names: Vec<&str>) -> Vec<String> {
    names.into_iter().map(str::to_owned).collect()
}

#[no_mangle]
pub extern "C" fn dataframe_pivot_v2(
    df_ptr: *const DataFrame,
    on: StrListArg,
    index: StrListArg,
    values: StrListArg,
    agg: i32,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        let on = owned(unsafe { str_list_arg(on) }?);
        polars_ensure!(!on.is_empty(), ComputeError: "a pivot needs an on column");
        let index = owned(unsafe { str_list_arg(index) }?);
        let values = owned(unsafe { str_list_arg(values) }?);
        let Some(agg_expr) = compat_pivot_agg(agg) else {
            polars_bail!(ComputeError: "unknown pivot aggregate {}", agg);
        };
        pivot_eager(df, on, index, values, agg_expr)
    })
}

#[no_mangle]
pub extern "C" fn dataframe_unpivot_v2(
    df_ptr: *const DataFrame,
    on: StrListArg,
    index: StrListArg,
) -> *mut DataFrame {
    boxed_result(|| {
        let df = unsafe { deref_arg(df_ptr, "dataframe") }?;
        let on = unsafe { str_list_arg(on) }?;
        let index = unsafe { str_list_arg(index) }?;
        let on = if on.is_empty() { None } else { Some(on) };
        df.unpivot(on, index)
    })
}
