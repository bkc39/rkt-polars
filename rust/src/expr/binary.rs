expr_binop!(expr_add, |a, b| a + b);
expr_binop!(expr_sub, |a, b| a - b);
expr_binop!(expr_mul, |a, b| a * b);
expr_binop!(expr_div, |a, b| a / b);
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
