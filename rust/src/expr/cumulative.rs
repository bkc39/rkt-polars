// ----- cumulative + shift / diff -----

expr_unop_u8!(expr_cum_sum, |e, rev| e.cum_sum(rev != 0));
expr_unop_u8!(expr_cum_prod, |e, rev| e.cum_prod(rev != 0));
expr_unop_u8!(expr_cum_min, |e, rev| e.cum_min(rev != 0));
expr_unop_u8!(expr_cum_max, |e, rev| e.cum_max(rev != 0));
expr_unop_u8!(expr_cum_count, |e, rev| e.cum_count(rev != 0));
