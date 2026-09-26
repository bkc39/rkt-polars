#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define ev (make-polars-eval))
@(define-runtime-path iris-csv-path "iris.csv")
@(ev `(define iris-csv ,(path->string iris-csv-path)))

@title[#:tag "concepts" #:style 'toc]{Concepts}

@see-reference["ref-fluent"]{the operators and contexts used here}

@local-table-of-contents[]

@section[#:tag "concepts-data-types"]{Data types and structures}

@subsection{Series}

A @deftech{series} is a typed, one-dimensional column. @racket[series] infers a
dtype or takes @racket[#:dtype]; @racket[polars-null] marks missing entries.

@examples[#:eval ev #:label #f
(series '(1 2 3 4 5) #:name "ints")
(define s1 (series '(1 2 3 4 5) #:name "ints"))
(define s2 (series '(1 2 3 4 5) #:name "uints" #:dtype 'u64))
(list (dtype s1) (dtype s2))
]

@subsection{Dataframe}

A @deftech{dataframe} is a collection of equal-length, uniquely named series.

@examples[#:eval ev #:label #f
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
df
]

@subsubsection{Inspecting a dataframe}

@examples[#:eval ev #:label #f
(head df 3)
(tail df 3)
(describe df)
]

API gaps: no @tt{glimpse}; no @tt{sample} / @tt{set_random_seed}.

@subsection{Schema}

@examples[#:eval ev #:label #f
(for ([name (column-names df)])
  (printf "~a: ~a\n" name (dtype (ref df #:columns name))))
]

The @racket[#:dtype] of each series plays the role of @tt{schema} /
@tt{schema_overrides}:

@examples[#:eval ev #:label #f
(dataframe
 (list (series '("Alice" "Ben" "Chloe" "Daniel") #:name "name")
       (series '(27 39 41 43) #:name "age" #:dtype 'u8)))
]

API gap: no schema accessor on a dataframe.

@subsection{Data types}

Dtype spellings accepted by @racket[series]' @racket[#:dtype]:

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

API gap: @racket[cast] is asymmetric with @racket[series] here --- it accepts
@emph{only} the long spellings, so @racket[(cast "v" 'f64)] is an error where
@racket[(series '(1) #:dtype 'f64)] is fine.

@examples[#:eval ev #:label #f
(dtype (cast (series '(1 2 3)) 'float64))
(eval:error (dtype (cast (series '(1 2 3)) 'f64)))
]

@section[#:tag "concepts-expressions-contexts"]{Expressions and contexts}

@subsection{Expressions}

An expression is a value; nothing runs until a context receives it.

@examples[#:eval ev #:label #f
(define bmi-expr (/ (col "weight") (pow (col "height") 2)))
bmi-expr
]

An expression prints as its plan, in the notation Polars itself uses: the
binding's @racket[/] is Polars' @tt{Divide} operator, shown as @tt{//}, and
@racket[pow] appears as a method suffix.

@subsection{Contexts}

@subsubsection[#:tag "concepts-select"]{select}

@examples[#:eval ev #:label #f
(~> df
    (select (alias bmi-expr "bmi")
            (~> bmi-expr mean (alias "avg_bmi"))
            (alias (lit 25) "ideal_max_bmi")))
(~> df
    (select (~> bmi-expr
                (- (mean bmi-expr))
                (/ (std bmi-expr))
                (alias "deviation"))))
]

@subsubsection[#:tag "concepts-with-columns"]{with-columns}

@examples[#:eval ev #:label #f
(~> df
    (with-columns (alias bmi-expr "bmi")
                  (~> bmi-expr mean (alias "avg_bmi"))
                  (alias (lit 25) "ideal_max_bmi")))
]

@subsubsection[#:tag "concepts-filter"]{filter}

@examples[#:eval ev #:label #f
(~> df
    (filter (and (is-between "birthdate"
                             (str-to-date (lit "1982-12-31"))
                             (str-to-date (lit "1996-01-01")))
                 (> (col "height") 1.7))))
]

@subsubsection[#:tag "concepts-group-by"]{group-by and aggregations}

Group keys may be expressions. A bare @racket[(col "name")] inside
@racket[agg] collects the group's values into a list.

@examples[#:eval ev #:label #f
(define decade
  (~> (col "birthdate") dt-year (/ 10) (* 10) (alias "decade")))
(~> df (group-by decade) (agg (col "name")))
(~> df
    (group-by decade (alias (< (col "height") 1.7) "short?"))
    (agg (col "name")))
(~> df
    (group-by decade (alias (< (col "height") 1.7) "short?"))
    (agg (~> (col "name") count (alias "len"))
         (~> (col "height") max (alias "tallest"))
         (~> (col "weight") mean (alias "avg_weight"))
         (~> (col "height") mean (alias "avg_height"))))
]

An aggregation followed by @racket[over] is computed per group but broadcast
back to every row of the group, so it goes in @racket[with-columns] rather
than @racket[agg]; the keys are whatever @racket[group-by] takes.

@examples[#:eval ev #:label #f
(~> df
    (with-columns (~> (col "height") mean (over decade) (alias "decade_avg_height"))))
]

API gaps: no @tt{pl.len()}; no multi-name @tt{col("weight", "height")}; no
@tt{name.prefix}.

@subsection{Expression expansion}

An expression over a multi-column @racket[col] expands to one expression
per matched column. @racket[(col 'float64)] is every @racket['float64]
column (@tt{pl.col(pl.Float64)}), and the outputs keep the matched names.

@examples[#:eval ev #:label #f
(define expr (* (col 'float64) 1.1))
(select df expr)
(define df2
  (dataframe (list (series '(1 2 3 4) #:name "ints")
                   (series '("A" "B" "C" "D") #:name "letters"))))
(select df2 expr)
]

API gap: no @tt{name.suffix}, so the expanded columns cannot be renamed
@tt{weight*1.1} / @tt{height*1.1}; they keep the matched names.

@section[#:tag "concepts-lazy-api"]{Lazy API}

Eager verbs run immediately on a @tech{dataframe}. The same verbs applied to a
@tech{lazyframe} (from @racket[lazy] or @racket[scan-csv]) build a query
plan that @racket[collect] optimises and runs. Here @racket[iris-csv] is a
path to a small CSV.

@examples[#:eval ev #:label #f
(define df-small (~> (read-csv iris-csv) (filter (> (col "sepal_length") 5))))
(~> df-small (group-by "species") (agg (mean "sepal_width")))
(define q
  (~> (scan-csv iris-csv)
      (filter (> (col "sepal_length") 5))
      (group-by "species")
      (agg (mean "sepal_width"))))
(collect q)
]

API gaps: no @tt{explain}; no schema-only @tt{LazyFrame}.

@(close-eval ev)
