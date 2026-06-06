#lang scribble/manual
@require[@for-label[polars
                    (only-in threading ~> ~>>)
                    @; polars re-exports generic ops (min max sum sort filter comparisons,
                    @; arithmetic + - * /, logical and/or/not, reverse, when) that shadow racket/base
                    (except-in racket/base min max sort filter reverse and or not when + - * / > < >= <= =)]]

@title[#:tag "guide"]{Guide}

This guide is a short, narrative tour of @racketmodname[polars], modelled
section by section on the upstream
@hyperlink["https://docs.pola.rs/user-guide/getting-started/"]{Polars
getting-started guide}. Every snippet below has a complete, runnable
counterpart under @tt{user-guide/getting-started/} in the project repository,
paired with an equivalent Python program so the two read side by side. Inside
the dev shell:

@verbatim|{
  racket user-guide/getting-started/series-and-dataframes.rkt
  python user-guide/getting-started/series_and_dataframes.py
}|

For the full definition of every binding mentioned here, see the
@secref["reference"].

@section{Series}

A @deftech{series} is a typed, one-dimensional column. The generic
@racket[series] constructor infers a dtype from the values, or takes an explicit
@racket[#:dtype]; @racket[polars-null] marks missing entries. A series is a
wrapper value (@racket[series?]) that prints in Polars' format.

@racketblock[
(define s (series '(1 2 3 4 5) #:name "a"))
(describe s)
(list (sum s) (min s) (max s) (mean s))
]

@racket[sum], @racket[min] and @racket[max] preserve the dtype; @racket[mean]
returns a @racket[float64]. The generic accessors @racket[len], @racket[dtype]
and @racket[null-count] read a series' length, element dtype and null count.

@section{DataFrames}

A @deftech{dataframe} is a collection of equal-length named series, built with
the @racket[dataframe] constructor. It is a wrapper value (@racket[dataframe?])
that prints as a Polars table, so plain @racket[display] (or @racket[~a]) shows
it. gregor datetimes become Polars datetime columns.

@racketblock[
(require gregor)
(define df
  (dataframe
   (list (series (list (datetime 2025 1 1) (datetime 2025 1 2)) #:name "date")
         (series '(1.0 2.0) #:name "float")
         (series '("a" "b") #:name "string"))))
(displayln df)
]

Inspect it with @racket[shape], @racket[height], @racket[width],
@racket[column-names], and @racket[describe]. @racket[ref] is the generic
accessor: an element out of a series, a column (or, with a list, a projection)
out of a dataframe.

@racketblock[
(shape df)
(column-names df)
(~> df (ref #:columns "float") (ref 0))
(ref df #:columns '("date" "float"))
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

@section[#:tag "method-chaining"]{Method chaining with @racket[~>]}

Polars' Python API reads as a chain of methods:

@verbatim|{
  df.filter(pl.col("value") > 15)
    .group_by("group")
    .agg(pl.col("value").sum().alias("sum_value"))
}|

The same pipeline reads as a thread-first @racket[~>] chain — re-provided from
@racketmodname[polars], so @racket[(require polars)] is all you need. Each step
takes the frame as its first argument, so the frame flows through the chain:

@racketblock[
(~> df
    (filter (> (col "value") 15))
    (group-by "group")
    (agg (alias (sum (col "value")) "sum_value")))
]

The comparison operators (@racket[>], @racket[<], @racket[>=], @racket[<=],
@racket[=], @racket[!=]) are overloaded: they build an @emph{expression} when an
operand is an expression — @racket[(> (col "value") 15)] — an eager boolean-mask
series when an operand is a series — @racket[(> (ref df #:columns "value") 15)] —
and otherwise fall back to the numeric @racketmodname[racket/base] operator, so
@racket[(> 3 2)] still works. @racket[filter], @racket[sort], @racket[group-by]
and @racket[agg] are data-first so they thread; @racket[group-by] returns a
deferred handle that @racket[agg] consumes. Inside @racket[agg], @racket[sum],
@racket[mean], @racket[min], @racket[max], @racket[count], @racket[first] and
friends take an expression (or a bare column name) and produce an aggregation,
matching @tt{col("value").sum()}. See @secref["ref-fluent"] for the full set,
including the @racket[first]/@racket[last] name clash with
@racketmodname[racket/list].

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
