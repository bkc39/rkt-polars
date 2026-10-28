use crate::prelude::*;
use crate::*;

#[no_mangle]
pub extern "C" fn lazyframe_join_v2(
    left_ptr: *const LazyFrame,
    right_ptr: *const LazyFrame,
    left_on: StrListArg,
    right_on: StrListArg,
    how: i32,
) -> *mut LazyFrame {
    boxed_unguarded(|| {
        let left = unsafe { deref_arg(left_ptr, "lazyframe") }?.clone();
        let right = unsafe { deref_arg(right_ptr, "lazyframe") }?.clone();
        let left_on = unsafe { str_list_arg(left_on) }?;
        let right_on = unsafe { str_list_arg(right_on) }?;
        if how == CompatJoinKind::Cross as i32 {
            return Ok(left.cross_join(right, None));
        }
        let join_type = match how {
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
        let left_exprs: Vec<Expr> = left_on.into_iter().map(col).collect();
        let right_exprs: Vec<Expr> = right_on.into_iter().map(col).collect();
        let args = JoinArgs::new(join_type);
        Ok(left.join(right, left_exprs, right_exprs, args))
    })
}

// ===== Phase A9: expr cast =====
//
// Takes a CompatDType *by value* (same struct used on the output side
// of `series_dtype`).  Unsupported tags (List/Array/Struct/Decimal/...)
// return null so the Racket side can raise rather than panic.
