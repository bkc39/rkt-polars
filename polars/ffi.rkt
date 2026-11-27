#lang racket/base

(require (only-in polars/private/csv dataframe-read-csv dataframe-write-csv lazyframe-scan-csv)
         (only-in polars/private/expr
                  LazyFrame-ptr? dataframe-filter-expr dataframe-group-by-agg dataframe-lazy
                  dataframe-select-exprs dataframe-with-columns
                  expr-add expr-alias expr-all expr-and expr-col expr-count expr-div
                  expr-dtype-col expr-eq expr-exclude expr-first expr-ge expr-gt expr-last
                  expr-le expr-lt expr-max expr-mean expr-median expr-meta-eq?
                  expr-meta-output-name expr-meta-root-names expr-min expr-mod expr-mul
                  expr-n-unique expr-ne expr-neg expr-not expr-or expr-over expr-sort
                  expr-sort-by expr-std expr-sub expr-sum expr-var expr-xor
                  lazyframe-collect lazyframe-drop lazyframe-explain lazyframe-filter
                  lazyframe-group-by-agg lazyframe-join lazyframe-select lazyframe-sort
                  lazyframe-with-columns)
         (only-in polars/private/foreign
                  DataFrame-ptr? Series-ptr?
                  dataframe->string dataframe-column dataframe-column-name
                  dataframe-column-names dataframe-drop dataframe-height dataframe-new
                  dataframe-select dataframe-shape dataframe-sort dataframe-vstack
                  dataframe-width display-dataframe
                  series-cast series-drop series-n-unique series-quantile series-sort
                  series-std series-var
                  series-new-bool series-new-bool/vec series-new-f32 series-new-f32/vec
                  series-new-f64 series-new-f64/vec series-new-i16 series-new-i16/vec
                  series-new-i32 series-new-i32/vec series-new-i64 series-new-i64/vec
                  series-new-i8 series-new-i8/vec series-new-null series-new-str
                  series-new-str/vec series-new-u16 series-new-u16/vec series-new-u32
                  series-new-u32/vec series-new-u64 series-new-u64/vec series-new-u8
                  series-new-u8/vec
                  series-max-f32 series-max-f64 series-max-i16 series-max-i32 series-max-i64
                  series-max-i8 series-max-u16 series-max-u32 series-max-u64 series-max-u8
                  series-mean-f32 series-mean-f64 series-mean-i16 series-mean-i32
                  series-mean-i64 series-mean-i8 series-mean-u16 series-mean-u32
                  series-mean-u64 series-mean-u8
                  series-min-f32 series-min-f64 series-min-i16 series-min-i32 series-min-i64
                  series-min-i8 series-min-u16 series-min-u32 series-min-u64 series-min-u8
                  series-sum-f32 series-sum-f64 series-sum-i16 series-sum-i32 series-sum-i64
                  series-sum-i8 series-sum-u16 series-sum-u32 series-sum-u64 series-sum-u8)
         (only-in polars/private/json
                  dataframe-read-json dataframe-read-json-lines dataframe-write-json
                  dataframe-write-json-lines lazyframe-scan-json-lines)
         (only-in polars/private/parquet
                  dataframe-read-parquet dataframe-write-parquet lazyframe-scan-parquet))

(provide Series-ptr? series-drop
         series-new-i8 series-new-i16 series-new-i32 series-new-i64
         series-new-u8 series-new-u16 series-new-u32 series-new-u64
         series-new-f32 series-new-f64 series-new-bool series-new-str
         series-new-i8/vec series-new-i16/vec series-new-i32/vec series-new-i64/vec
         series-new-u8/vec series-new-u16/vec series-new-u32/vec series-new-u64/vec
         series-new-f32/vec series-new-f64/vec series-new-bool/vec series-new-str/vec
         series-new-null
         series-sum-i8 series-sum-i16 series-sum-i32 series-sum-i64
         series-sum-u8 series-sum-u16 series-sum-u32 series-sum-u64
         series-sum-f32 series-sum-f64
         series-min-i8 series-min-i16 series-min-i32 series-min-i64
         series-min-u8 series-min-u16 series-min-u32 series-min-u64
         series-min-f32 series-min-f64
         series-max-i8 series-max-i16 series-max-i32 series-max-i64
         series-max-u8 series-max-u16 series-max-u32 series-max-u64
         series-max-f32 series-max-f64
         series-mean-i8 series-mean-i16 series-mean-i32 series-mean-i64
         series-mean-u8 series-mean-u16 series-mean-u32 series-mean-u64
         series-mean-f32 series-mean-f64
         series-n-unique series-std series-var series-quantile series-cast series-sort

         DataFrame-ptr? dataframe-drop
         dataframe-new dataframe-shape dataframe-height dataframe-width
         dataframe-column dataframe-column-name dataframe-column-names dataframe-select
         display-dataframe dataframe->string dataframe-vstack dataframe-sort

         dataframe-read-parquet lazyframe-scan-parquet dataframe-write-parquet
         dataframe-read-csv lazyframe-scan-csv dataframe-write-csv
         dataframe-read-json dataframe-write-json
         dataframe-read-json-lines lazyframe-scan-json-lines dataframe-write-json-lines

         LazyFrame-ptr? lazyframe-drop dataframe-lazy lazyframe-collect lazyframe-explain
         lazyframe-select lazyframe-with-columns lazyframe-filter lazyframe-group-by-agg
         lazyframe-sort lazyframe-join

         expr-alias expr-col expr-all expr-exclude expr-dtype-col
         expr-meta-output-name expr-meta-root-names expr-meta-eq? expr-over
         expr-add expr-sub expr-mul expr-div expr-mod expr-neg
         expr-gt expr-lt expr-ge expr-le expr-eq expr-ne
         expr-and expr-or expr-xor expr-not
         expr-sum expr-mean expr-min expr-max expr-median expr-count expr-n-unique
         expr-first expr-last expr-std expr-var
         expr-sort expr-sort-by
         dataframe-select-exprs dataframe-with-columns dataframe-filter-expr
         dataframe-group-by-agg)
