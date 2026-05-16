// Aggregations: collapse a column to a single value when used inside
// .agg(...), or to a length-1 result when used at the top level.
expr_unop!(expr_sum, |e| e.sum());
expr_unop!(expr_mean, |e| e.mean());
expr_unop!(expr_min, |e| e.min());
expr_unop!(expr_max, |e| e.max());
expr_unop!(expr_count, |e| e.count());
expr_unop!(expr_n_unique, |e| e.n_unique());
expr_unop!(expr_first, |e| e.first());
expr_unop!(expr_last, |e| e.last());
expr_unop!(expr_median, |e| e.median());

// std / var carry a ddof parameter (degrees-of-freedom adjustment);
// matches polars and pandas defaults of 1 on the Racket side.
expr_unop_u8!(expr_std, |e, ddof| e.std(ddof));
expr_unop_u8!(expr_var, |e, ddof| e.var(ddof));
