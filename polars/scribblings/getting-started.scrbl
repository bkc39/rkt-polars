#lang scribble/manual
@require[@for-label[polars
                    @; polars re-exports generic min/max that shadow racket/base
                    (except-in racket/base min max)]]

@title[#:tag "top"]{Getting started with rkt-polars}
@author{bkc}

This guide is a short tour of @racketmodname[polars], modelled section by
section on the upstream
@hyperlink["https://docs.pola.rs/user-guide/getting-started/"]{Polars
getting-started guide}. Every snippet below has a complete, runnable
counterpart under @tt{user-guide/getting-started/} in the project repository,
paired with an equivalent Python program so the two read side by side. Inside
the dev shell:

@verbatim|{
  racket user-guide/getting-started/series-and-dataframes.rkt
  python user-guide/getting-started/series_and_dataframes.py
}|

@section{Series}

A @deftech{series} is a typed, one-dimensional column. The generic
@racket[series] constructor infers a dtype from the values, or takes an explicit
@racket[#:dtype]; @racket[polars-null] marks missing entries.

@racketblock[
(define s (series '(1 2 3 4 5) #:name "a"))
(describe s)
(list (sum s) (min s) (max s) (mean s))
]

@racket[sum], @racket[min] and @racket[max] preserve the dtype; @racket[mean]
returns a @racket[float64].

@section{DataFrames}

A @deftech{dataframe} is a collection of equal-length named series, built with
@racket[dataframe-new]. gregor datetimes become Polars datetime columns.

@racketblock[
(require gregor)
(define df
  (dataframe-new
   (list (series (list (datetime 2025 1 1) (datetime 2025 1 2)) #:name "date")
         (series '(1.0 2.0) #:name "float")
         (series '("a" "b") #:name "string"))))
(display-dataframe df)
]

View it with @racket[dataframe-shape], @racket[dataframe-head],
@racket[dataframe-tail], and @racket[describe]. @racket[ref] is the generic
accessor: a column out of a dataframe, an element out of a series.

@racketblock[
(ref (ref df "float") 0)
]

@section{Reading & writing}

DataFrames round-trip through CSV, Parquet, and newline-delimited JSON.

@racketblock[
(dataframe-write-csv df "data.csv")
(dataframe-read-csv "data.csv")

(dataframe-write-parquet df "data.parquet")
(dataframe-read-parquet "data.parquet")

(dataframe-write-json-lines df "data.jsonl")
(dataframe-read-json-lines "data.jsonl")
]

@section{Expressions}

Expressions (@racket[col], @racket[expr-mul], @racket[expr-sum], @racket[expr-alias],
…) describe transformations, and are reused across the @emph{select},
@emph{with_columns}, @emph{filter}, and @emph{group_by/agg} contexts.

@racketblock[
(code:comment "select: choose and transform columns")
(dataframe-select-exprs
 df
 (list (col "group")
       (expr-alias (expr-mul (col "value") (col "cost")) "spend")))

(code:comment "with_columns: add derived columns")
(dataframe-with-columns
 df
 (list (expr-alias (expr-mul (col "value") 2) "double_value")))

(code:comment "filter: keep matching rows")
(dataframe-filter-expr
 df
 (expr-and (expr-gt (col "value") 15)
           (expr-lt (col "cost") 3.0)))

(code:comment "group_by + agg: aggregate per group")
(dataframe-group-by-agg
 df '("group")
 (list (expr-alias (expr-sum (col "value")) "sum_value")
       (expr-alias (expr-count (col "value")) "n")))
]

@section{Combining DataFrames}

Join two frames on a key (eagerly, or as part of a lazy plan), and stack rows
with @racket[dataframe-vstack].

@racketblock[
(lazyframe-collect
 (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                 #:on '("uid") #:how 'inner))

(dataframe-vstack users more-users)
]

For complete, runnable versions of all of the above — including the Python
references — see @tt{user-guide/getting-started/}.
