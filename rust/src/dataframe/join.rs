use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn dataframe_unique(df_ptr: *mut DataFrame) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    match df.unique::<String, String>(
        None,
        polars::prelude::UniqueKeepStrategy::Any,
        None,
    ) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dataframe_drop_nulls(
    df_ptr: *mut DataFrame,
) -> *mut DataFrame {
    if df_ptr.is_null() {
        return ptr::null_mut();
    }
    let df = unsafe { &*df_ptr };
    let none: Option<&[String]> = None;
    match df.drop_nulls(none) {
        Ok(out) => Box::into_raw(Box::new(out)),
        Err(_) => ptr::null_mut(),
    }
}

#[repr(i32)]
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum CompatJoinKind {
    Inner = 1,
    Left = 2,
    Outer = 3,
    Cross = 4,
    Semi = 5,
    Anti = 6,
}

fn join_frames(
    left: &DataFrame,
    right: &DataFrame,
    left_on: &[&str],
    right_on: &[&str],
    how: i32,
) -> PolarsResult<DataFrame> {
    use polars::prelude::{CrossJoin, JoinType};
    let join_type = match how {
        x if x == CompatJoinKind::Cross as i32 => {
            return left.cross_join(
                right,
                None,
                None,
                polars::prelude::MaintainOrderJoin::LeftRight,
            );
        }
        x if x == CompatJoinKind::Inner as i32 => JoinType::Inner,
        x if x == CompatJoinKind::Left as i32 => JoinType::Left,
        x if x == CompatJoinKind::Outer as i32 => JoinType::Full,
        x if x == CompatJoinKind::Semi as i32 => JoinType::Semi,
        x if x == CompatJoinKind::Anti as i32 => JoinType::Anti,
        _ => polars_bail!(InvalidOperation: "unknown join kind {}", how),
    };
    polars_ensure!(
        !left_on.is_empty() && !right_on.is_empty(),
        InvalidOperation: "a join needs at least one key column"
    );
    polars_ensure!(
        left_on.len() == right_on.len(),
        InvalidOperation: "the number of columns given as join key (left: {}, right:{}) should be equal",
        left_on.len(),
        right_on.len()
    );
    let args = polars::prelude::JoinArgs::new(join_type);
    left.join(right, left_on, right_on, args, None)
}

#[no_mangle]
pub extern "C" fn dataframe_join_v2(
    left_ptr: *const DataFrame,
    right_ptr: *const DataFrame,
    left_on: StrListArg,
    right_on: StrListArg,
    how: i32,
) -> *mut DataFrame {
    boxed_result(|| {
        let left = unsafe { deref_arg(left_ptr, "dataframe") }?;
        let right = unsafe { deref_arg(right_ptr, "dataframe") }?;
        let left_on = unsafe { str_list_arg(left_on) }?;
        let right_on = unsafe { str_list_arg(right_on) }?;
        join_frames(left, right, &left_on, &right_on, how)
    })
}
