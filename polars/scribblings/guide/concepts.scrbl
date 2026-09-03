#lang scribble/manual
@require[@for-label[polars
                    (only-in threading ~> ~>>)
                    (except-in racket/base min max sort filter reverse and or not when + - * / > < >= <= = abs round floor sqrt exp log)]]

@title[#:tag "concepts"]{Concepts}

Mirrors the upstream
@hyperlink["https://docs.pola.rs/user-guide/concepts/"]{Concepts} chapter.
Scripts: @tt{user-guide/concepts/}.

@section[#:tag "concepts-data-types"]{Data types and structures}

@subsection{Series}

A @deftech{series} is a typed, one-dimensional column. @racket[series] infers a
dtype or takes @racket[#:dtype]; @racket[polars-null] marks missing entries.

@racketblock[
(define s (series '(1 2 3 4 5) #:name "ints"))

(define s1 (series '(1 2 3 4 5) #:name "ints"))
(define s2 (series '(1 2 3 4 5) #:name "uints" #:dtype 'u64))
(list (dtype s1) (dtype s2))
]

@verbatim|{
'(int64 uint64)
}|

@subsection{Dataframe}

A @deftech{dataframe} is a collection of equal-length, uniquely named series.

@racketblock[
(define df
  (~> (dataframe
       (list (series '("Alice Archer" "Ben Brown" "Chloe Cooper" "Daniel Donovan")
                     #:name "name")
             (series (list (datetime 1997 1 10) (datetime 1985 2 15)
                           (datetime 1983 3 22) (datetime 1981 4 30))
                     #:name "birthdate")
             (series '(57.9 72.5 53.6 83.1) #:name "weight")
             (series '(1.56 1.77 1.65 1.75) #:name "height")))
      (with-columns (cast "birthdate" 'date))))
]

@subsubsection{Inspecting a dataframe}

@racketblock[
(head df 3)
(tail df 3)
(describe df)
]

API gaps: no @tt{glimpse}; no @tt{sample} / @tt{set_random_seed}.

@subsection{Schema}

@racketblock[
(for ([name (column-names df)])
  (printf "~a: ~a\n" name (dtype (ref df #:columns name))))
]

@verbatim|{
name: string
birthdate: date
weight: float64
height: float64
}|

The @racket[#:dtype] of each series plays the role of @tt{schema} /
@tt{schema_overrides}:

@racketblock[
(dataframe
 (list (series '("Alice" "Ben" "Chloe" "Daniel") #:name "name")
       (series '(27 39 41 43) #:name "age" #:dtype 'u8)))
]

API gap: no schema accessor on a dataframe.

@subsection{Data types}

Dtype spellings accepted by @racket[series] and @racket[cast]:

@tabular[#:style 'boxed #:sep @hspace[2]
  (list (list @bold{Racket} @bold{Polars})
        (list @racket['bool] "Boolean")
        (list @elem{@racket['i8] @racket['i16] @racket['i32] @racket['i64]} "Int8 … Int64")
        (list @elem{@racket['u8] @racket['u16] @racket['u32] @racket['u64]} "UInt8 … UInt64")
        (list @elem{@racket['f32] @racket['f64]} "Float32, Float64")
        (list @racket['str] "String")
        (list @racket['date] "Date")
        (list @racket['time] "Time")
        (list @elem{@racket['datetime] or @racket['(datetime milliseconds)]} "Datetime")
        (list "—" "Decimal, Binary, Duration, Array, List, Categorical, Enum, Struct"))]

Long spellings (@racket['int32], @racket['float64], @racket['string], …)
are accepted too. Values that mix ints and floats promote to
@racket['f64]; see @secref["promotion"].

@section[#:tag "concepts-expressions-contexts"]{Expressions and contexts}

@subsection{Expressions}

An expression is a value; nothing runs until a context receives it.

@racketblock[
(define bmi-expr (/ (col "weight") (pow (col "height") 2)))
]

API gap: an expression prints as an opaque pointer, not as its plan.

@subsection{Contexts}

@subsubsection[#:tag "concepts-select"]{select}

@racketblock[
(~> df
    (select (alias bmi-expr "bmi")
            (alias (mean bmi-expr) "avg_bmi")
            (alias (lit 25) "ideal_max_bmi")))

(~> df
    (select (alias (/ (- bmi-expr (mean bmi-expr)) (std bmi-expr)) "deviation")))
]

@verbatim|{
shape: (4, 3)
┌───────────┬───────────┬───────────────┐
│ bmi       ┆ avg_bmi   ┆ ideal_max_bmi │
│ ---       ┆ ---       ┆ ---           │
│ f64       ┆ f64       ┆ i32           │
╞═══════════╪═══════════╪═══════════════╡
│ 23.791913 ┆ 23.438973 ┆ 25            │
│ 23.141498 ┆ 23.438973 ┆ 25            │
│ 19.687787 ┆ 23.438973 ┆ 25            │
│ 27.134694 ┆ 23.438973 ┆ 25            │
└───────────┴───────────┴───────────────┘
}|

@subsubsection[#:tag "concepts-with-columns"]{with-columns}

@racketblock[
(~> df
    (with-columns (alias bmi-expr "bmi")
                  (alias (mean bmi-expr) "avg_bmi")
                  (alias (lit 25) "ideal_max_bmi")))
]

@subsubsection[#:tag "concepts-filter"]{filter}

@racketblock[
(~> df
    (filter (and (is-between "birthdate"
                             (cast (lit "1982-12-31") 'date)
                             (cast (lit "1996-01-01") 'date))
                 (> (col "height") 1.7))))
]

@subsubsection[#:tag "concepts-group-by"]{group-by and aggregations}

Group keys may be expressions. A bare @racket[(col "name")] inside
@racket[agg] collects the group's values into a list.

@racketblock[
(define decade (alias (* (/ (dt-year "birthdate") 10) 10) "decade"))

(~> df (group-by decade) (agg (col "name")))

(~> df
    (group-by decade (alias (< (col "height") 1.7) "short?"))
    (agg (col "name")))

(~> df
    (group-by decade (alias (< (col "height") 1.7) "short?"))
    (agg (alias (count "name") "len")
         (alias (max "height") "tallest")
         (alias (mean "weight") "avg_weight")
         (alias (mean "height") "avg_height")))
]

@verbatim|{
shape: (3, 6)
┌────────┬────────┬─────┬─────────┬────────────┬────────────┐
│ decade ┆ short? ┆ len ┆ tallest ┆ avg_weight ┆ avg_height │
│ ---    ┆ ---    ┆ --- ┆ ---     ┆ ---        ┆ ---        │
│ i32    ┆ bool   ┆ u32 ┆ f64     ┆ f64        ┆ f64        │
╞════════╪════════╪═════╪═════════╪════════════╪════════════╡
│ 1980   ┆ false  ┆ 2   ┆ 1.77    ┆ 77.8       ┆ 1.76       │
│ 1990   ┆ true   ┆ 1   ┆ 1.56    ┆ 57.9       ┆ 1.56       │
│ 1980   ┆ true   ┆ 1   ┆ 1.65    ┆ 53.6       ┆ 1.65       │
└────────┴────────┴─────┴─────────┴────────────┴────────────┘
}|

API gaps: no @tt{pl.len()}; no multi-column @tt{col(...)}; no
@tt{name.prefix}.

@subsection{Expression expansion}

API gap: no dtype selectors (@tt{col(pl.Float64)}) and no @tt{name.suffix},
so an expression cannot expand over "all float columns"; spell them out.

@racketblock[
(~> df
    (select (alias (* (col "weight") 1.1) "weight*1.1")
            (alias (* (col "height") 1.1) "height*1.1")))
]

@section[#:tag "concepts-lazy-api"]{Lazy API}

Eager verbs run immediately on a @tech{dataframe}. The same verbs applied to a
@tech{lazyframe} (from @racket[lazy] or @racket[scan-csv]) build a query
plan that @racket[collect] optimises and runs.

@racketblock[
(define df (read-csv "iris.csv"))
(define df-small (filter df (> (col "sepal_length") 5)))
(define df-agg (~> df-small (group-by "species") (agg (mean "sepal_width"))))

(define q
  (~> (scan-csv "iris.csv")
      (filter (> (col "sepal_length") 5))
      (group-by "species")
      (agg (mean "sepal_width"))))

(collect q)
]

API gaps: no @tt{explain}; no schema-only @tt{LazyFrame}.
