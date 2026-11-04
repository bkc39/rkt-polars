use crate::prelude::*;

expr_binop!(expr_add, |a, b| a + b);
expr_binop!(expr_sub, |a, b| a - b);
expr_binop!(expr_mul, |a, b| a * b);
expr_binop!(expr_div, integer_floor_div);
expr_binop!(expr_mod, |a, b| a % b);

expr_binop!(expr_gt, |a, b| a.gt(b));
expr_binop!(expr_lt, |a, b| a.lt(b));
expr_binop!(expr_ge, |a, b| a.gt_eq(b));
expr_binop!(expr_le, |a, b| a.lt_eq(b));
expr_binop!(expr_eq, |a, b| a.eq(b));
expr_binop!(expr_ne, |a, b| a.neq(b));

expr_binop!(expr_and, |a, b| a.and(b));
expr_binop!(expr_or, |a, b| a.or(b));
expr_binop!(expr_xor, |a, b| a.xor(b));

fn integer_floor_div(a: Expr, b: Expr) -> Expr {
    let quotient = a.clone() / b.clone();
    let mut floored =
        quotient.map_many(floor_integer_quotient, &[a, b], quotient_field);
    if let Expr::AnonymousFunction { fmt_str, .. } = &mut floored {
        *fmt_str = Box::new(PlSmallStr::from_static(FLOOR_IF_INTEGER));
    }
    floored
}

const FLOOR_IF_INTEGER: &str = "floor_if_integer";

/// The operands of a division `integer_floor_div` built.
pub(crate) fn floor_div_operands(e: &Expr) -> Option<(&Expr, &Expr)> {
    match e {
        Expr::AnonymousFunction { input, fmt_str, .. }
            if fmt_str.as_str() == FLOOR_IF_INTEGER =>
        {
            match &input[..] {
                [_, a, b] => Some((a, b)),
                _ => None,
            }
        }
        _ => None,
    }
}

fn integer_like(dtype: &DataType) -> bool {
    dtype.is_integer() || dtype.is_bool() || dtype.is_null()
}

fn quotient_field(_: &Schema, fields: &[Field]) -> PolarsResult<Field> {
    let dtype = if fields[1].dtype.is_null() && fields[2].dtype.is_null() {
        DataType::Float64
    } else {
        // polars asks once before it coerces the quotient's operands, when
        // a dynamic literal may leave it unknown, and requires a known dtype;
        // it asks again once they are coerced.
        match fields[0].dtype.clone().materialize_unknown(true)? {
            DataType::Unknown(_) => DataType::Float64,
            dtype => dtype,
        }
    };
    Ok(Field::new(fields[0].name.clone(), dtype))
}

fn floor_integer_quotient(columns: &mut [Column]) -> PolarsResult<Column> {
    let quotient = std::mem::take(&mut columns[0]);
    if columns[1].dtype().is_null() && columns[2].dtype().is_null() {
        Ok(Column::full_null(
            quotient.name().clone(),
            quotient.len(),
            &DataType::Float64,
        ))
    } else if quotient.dtype() == &DataType::Float64
        && integer_like(columns[1].dtype())
        && integer_like(columns[2].dtype())
    {
        Ok(quotient
            .as_materialized_series()
            .f64()?
            .apply_values(f64::floor)
            .into_column())
    } else {
        Ok(quotient)
    }
}
