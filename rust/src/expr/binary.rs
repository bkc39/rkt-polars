use std::sync::LazyLock;

use crate::guard_panic;
use crate::prelude::*;

expr_binop!(expr_add, |a, b| a + b);
expr_binop!(expr_sub, |a, b| a - b);
expr_binop!(expr_mul, |a, b| a * b);
expr_binop!(expr_div, floor_if_integer);
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

static FLOOR_IF_INTEGER: LazyLock<Expr> =
    LazyLock::new(|| udf(floor_integer_quotient, quotient_field));

static NULL_AS_FLOAT: LazyLock<Expr> =
    LazyLock::new(|| udf(null_as_float, null_as_float_field));

fn udf(
    function: fn(&mut [Column]) -> PolarsResult<Column>,
    field: fn(&Schema, &[Field]) -> PolarsResult<Field>,
) -> Expr {
    lit(Null {}).map_many(function, &[], field)
}

fn anonymous(udf: &Expr, name: &'static str, input: Vec<Expr>) -> Expr {
    let Expr::AnonymousFunction {
        function, options, ..
    } = udf
    else {
        unreachable!("map_many builds an anonymous function");
    };
    Expr::AnonymousFunction {
        input,
        function: function.clone(),
        options: *options,
        fmt_str: Box::new(PlSmallStr::from_static(name)),
    }
}

fn inputs_of<'a>(udf: &Expr, e: &'a Expr) -> Option<&'a [Expr]> {
    match (udf, e) {
        (
            Expr::AnonymousFunction { function: f, .. },
            Expr::AnonymousFunction {
                function, input, ..
            },
        ) if f == function => Some(input),
        _ => None,
    }
}

fn floor_if_integer(a: Expr, b: Expr) -> Expr {
    if dynamic_integer_quotient(&a, &b) {
        return a.floor_div(b);
    }
    let (wa, wb) = (witness(&a), witness(&b));
    anonymous(&FLOOR_IF_INTEGER, "floor_if_integer", vec![a / b, wa, wb])
}

fn reads_frame(e: &Expr) -> bool {
    e.into_iter().any(|e| {
        matches!(
            e,
            Expr::Column(_)
                | Expr::Len
                | Expr::Selector(_)
                | Expr::Eval { .. }
                | Expr::Field(_)
                | Expr::Element
        )
    })
}

fn dynamic_integer_quotient(a: &Expr, b: &Expr) -> bool {
    !reads_frame(a)
        && !reads_frame(b)
        && matches!(
            guard_panic(|| {
                (a.clone() / b.clone()).to_field(&Schema::default()).ok()
            }),
            Some(Field {
                dtype: DataType::Unknown(UnknownKind::Int(_)),
                ..
            })
        )
}

fn floor_if_integer_inputs(e: &Expr) -> Option<&[Expr; 3]> {
    inputs_of(&FLOOR_IF_INTEGER, e)?.try_into().ok()
}

pub(crate) fn floor_div_quotient(e: &Expr) -> Option<&Expr> {
    floor_if_integer_inputs(e).map(|[quotient, _, _]| quotient)
}

pub(crate) fn without_floors(e: Expr) -> Expr {
    e.map_expr(|e| floor_div_quotient(&e).cloned().unwrap_or(e))
}

fn typed_like_floors(e: Expr) -> Expr {
    e.map_expr(|e| match floor_div_quotient(&e) {
        Some(quotient) => {
            anonymous(&NULL_AS_FLOAT, "null_as_float", vec![quotient.clone()])
        }
        None => e,
    })
}

fn witness(operand: &Expr) -> Expr {
    let typed = typed_like_floors(operand.clone());
    let leaf = matches!(typed, Expr::Column(_) | Expr::Literal(_));
    let expands = typed.into_iter().any(|e| {
        matches!(
            e,
            Expr::Selector(_)
                | Expr::Eval { .. }
                | Expr::Field(_)
                | Expr::Element
        )
    });
    let reads = typed
        .into_iter()
        .any(|e| matches!(e, Expr::Column(_) | Expr::Len));
    if leaf || expands || !reads {
        typed
    } else {
        lit(Null {}).cast(DataTypeExpr::OfExpr(Box::new(typed)))
    }
}

fn integer_like(dtype: &DataType) -> bool {
    dtype.is_integer() || dtype.is_bool() || dtype.is_null()
}

fn quotient_field(_: &Schema, fields: &[Field]) -> PolarsResult<Field> {
    let [quotient, a, b] = fields else {
        polars_bail!(ComputeError: "floor_if_integer takes three inputs");
    };
    let materialized = quotient.dtype.clone().materialize_unknown(true)?;
    let dtype = match (&a.dtype, &b.dtype, materialized) {
        (DataType::Null, DataType::Null, _) | (_, _, DataType::Unknown(_)) => {
            DataType::Float64
        }
        (_, _, dtype) => dtype,
    };
    Ok(Field::new(quotient.name.clone(), dtype))
}

fn floor_integer_quotient(columns: &mut [Column]) -> PolarsResult<Column> {
    let [quotient, a, b] = columns else {
        polars_bail!(ComputeError: "floor_if_integer takes three inputs");
    };
    let quotient = std::mem::take(quotient);
    match (a.dtype(), b.dtype(), quotient.dtype()) {
        (DataType::Null, DataType::Null, _) => Ok(Column::full_null(
            quotient.name().clone(),
            quotient.len(),
            &DataType::Float64,
        )),
        (a, b, DataType::Float64) if integer_like(a) && integer_like(b) => {
            Ok(quotient
                .as_materialized_series()
                .f64()?
                .apply_values(f64::floor)
                .into_column())
        }
        _ => Ok(quotient),
    }
}

fn null_as_float_field(_: &Schema, fields: &[Field]) -> PolarsResult<Field> {
    let [quotient] = fields else {
        polars_bail!(ComputeError: "null_as_float takes one input");
    };
    let dtype = match quotient.dtype.clone().materialize_unknown(true)? {
        DataType::Null | DataType::Unknown(_) => DataType::Float64,
        dtype => dtype,
    };
    Ok(Field::new(quotient.name.clone(), dtype))
}

fn null_as_float(columns: &mut [Column]) -> PolarsResult<Column> {
    let [quotient] = columns else {
        polars_bail!(ComputeError: "null_as_float takes one input");
    };
    let quotient = std::mem::take(quotient);
    match quotient.dtype() {
        DataType::Null => Ok(Column::full_null(
            quotient.name().clone(),
            quotient.len(),
            &DataType::Float64,
        )),
        _ => Ok(quotient),
    }
}
