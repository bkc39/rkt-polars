expr_unop!(expr_not, |e| e.not());
expr_unop!(expr_neg, |e| -e);
expr_unop!(expr_is_null, |e| e.is_null());
expr_unop!(expr_is_not_null, |e| e.is_not_null());

// Null / NaN handling.
expr_unop!(expr_drop_nulls, |e| e.drop_nulls());
expr_unop!(expr_drop_nans, |e| e.drop_nans());
expr_unop!(expr_is_nan, |e| e.is_nan());
expr_unop!(expr_is_not_nan, |e| e.is_not_nan());
expr_unop!(expr_is_finite, |e| e.is_finite());
expr_unop!(expr_is_infinite, |e| e.is_infinite());
expr_binop!(expr_fill_null, |a, b| a.fill_null(b));
expr_binop!(expr_fill_nan, |a, b| a.fill_nan(b));
