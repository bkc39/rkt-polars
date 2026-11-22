#lang racket/base

(require polars/private/compat-dtype
         polars/private/compat-ffi
         polars/private/dataframe-core
         polars/private/dataframe-ops
         polars/private/owned
         polars/private/reason
         polars/private/series-core
         polars/private/series-new
         polars/private/series-ops
         polars/private/series-ref)

(provide (except-out (all-from-out polars/private/compat-dtype)
                     dtype-aliases dtype-spec? normalize-dtype)
         (all-from-out polars/private/compat-ffi
                       polars/private/dataframe-core
                       polars/private/dataframe-ops
                       polars/private/owned
                       polars/private/reason
                       polars/private/series-core
                       polars/private/series-new
                       polars/private/series-ops
                       polars/private/series-ref))

(module+ internal
  (require (only-in (submod polars/private/compat-ffi internal) block-reader)
           (only-in (submod polars/private/dataframe-core internal)
                    dataframe-column/who dataframe-drop-columns/who dataframe-drop-nulls/who
                    dataframe-head dataframe-head/who dataframe-hstack dataframe-hstack/who
                    dataframe-rename/who dataframe-select/who dataframe-slice dataframe-slice/who
                    dataframe-tail dataframe-tail/who dataframe-unique/who dataframe-vstack
                    dataframe-vstack/who dataframe-with-column/who)
           (only-in (submod polars/private/dataframe-ops internal)
                    dataframe-join dataframe-join-asof dataframe-join-asof/who dataframe-join/who
                    dataframe-sort dataframe-sort/who)
           (only-in (submod polars/private/owned internal) dataframe-drop series-drop)
           (only-in (submod polars/private/reason internal) define-reasoned)
           (only-in (submod polars/private/series-core internal)
                    named series-rename/who series-strings)
           (only-in (submod polars/private/series-new internal) series-new-null)
           (only-in (submod polars/private/series-ops internal)
                    series-add-i32 series-add-i64 series-add-u32 series-add-u64 series-div-i32
                    series-div-i64 series-div-u32 series-div-u64 series-drop-nulls/who
                    series-eq-i32 series-ge-i32 series-gt-i32 series-head series-head/who
                    series-le-i32 series-lt-i32 series-mod-i32 series-mod-i64 series-mod-u32
                    series-mod-u64 series-mul-i32 series-mul-i64 series-mul-u32 series-mul-u64
                    series-n-unique/who series-ne-i32 series-reverse/who series-slice
                    series-slice/who series-sort series-sort/who series-std series-std/who
                    series-sub-i32 series-sub-i64 series-sub-u32 series-sub-u64 series-tail
                    series-tail/who series-unique/who series-var series-var/who typed-reductions)
           (only-in (submod polars/private/series-ref internal) series-ref-bytes series-ref-cat))
  (provide dataframe-drop-nulls/who dataframe-head/who dataframe-slice/who dataframe-tail/who
           dataframe-unique/who series-drop-nulls/who series-head/who series-n-unique/who
           series-rename/who series-reverse/who series-slice/who series-sort/who series-std/who
           series-tail/who series-unique/who
           series-cast-to series-ref-datetime series-var/who typed-reductions define-reasoned named)
  (provide block-reader dataframe-column/who dataframe-drop dataframe-drop-columns/who
           dataframe-head dataframe-hstack dataframe-hstack/who dataframe-join
           dataframe-join-asof dataframe-join-asof/who dataframe-join/who dataframe-rename/who
           dataframe-select/who dataframe-slice dataframe-sort dataframe-sort/who dataframe-tail
           dataframe-vstack dataframe-vstack/who dataframe-with-column/who series-add-i32 series-add-i64 series-add-u32 series-add-u64
           series-div-i32 series-div-i64 series-div-u32 series-div-u64 series-drop series-eq-i32
           series-ge-i32 series-gt-i32 series-head series-le-i32 series-lt-i32 series-mod-i32
           series-mod-i64 series-mod-u32 series-mod-u64 series-mul-i32 series-mul-i64
           series-mul-u32 series-mul-u64 series-ne-i32 series-new-null series-ref-bytes
           series-ref-cat series-slice series-sort series-std series-strings series-sub-i32
           series-sub-i64 series-sub-u32 series-sub-u64 series-tail series-var))
