#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define-runtime-path data-dir "../data")
@(define ev (make-polars-eval #:directory data-dir))

@title[#:tag "io-parquet"]{Parquet}

@see-reference["ref-fluent"]{@racket[read-parquet], @racket[scan-parquet] and @racket[write-parquet]}

Loading or writing Parquet files is fast: unlike CSV, Parquet stores data
by column, as a @tech{dataframe} holds it in memory, which compresses better
and reads faster.

@section[#:tag "io-parquet-read"]{Read}

@racket[read-parquet] loads a Parquet file into a dataframe.
@filepath{flights.parquet} holds the 102 rows of @filepath{flights.tsv}:

@examples[#:eval ev #:label #f
(define flights (read-parquet "flights.parquet"))
(shape flights)
(~> flights (select "carrier" "dep_delay" "time_hour") (head 3))
]

@section[#:tag "io-parquet-write"]{Write}

@examples[#:eval ev #:hidden
(require racket/file)
(define dir (make-temporary-directory "polars-guide-~a"))
(define path (build-path dir "path.parquet"))
]

@racket[write-parquet] saves a dataframe to Parquet:

@examples[#:eval ev #:label #f
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-parquet df path)
(read-parquet path)
]

@section[#:tag "io-parquet-scan"]{Scan}

Polars can also @emph{scan} a Parquet input. Scanning delays the actual
parsing of the file and returns a @tech{lazyframe}, a lazy computation
holder; @racket[collect] runs it. See @secref["concepts-lazy-api"] for why
that is desirable.

@examples[#:eval ev #:label #f
(scan-parquet path)
(collect (scan-parquet path))
]

@section[#:tag "io-parquet-dtypes"]{Dtypes}

A CSV file holds text, so a column read back from one is whatever the reader
infers. Parquet records each column's dtype, so Categorical, Enum, Decimal
and datetime columns come back as they went out. @filepath{produce.parquet}
has one of each of the first three:

@examples[#:eval ev #:label #f
(define produce (read-parquet "produce.parquet"))
produce
(write-csv produce (build-path dir "produce.csv"))
(read-csv (build-path dir "produce.csv"))
(write-parquet produce (build-path dir "produce.parquet"))
(read-parquet (build-path dir "produce.parquet"))
]

And a datetime column:

@examples[#:eval ev #:label #f
(define stamps (select flights "time_hour"))
(write-csv stamps (build-path dir "stamps.csv"))
(dtype (ref (read-csv (build-path dir "stamps.csv")) "time_hour"))
(write-parquet stamps (build-path dir "stamps.parquet"))
(dtype (ref (read-parquet (build-path dir "stamps.parquet")) "time_hour"))
]

@section[#:tag "io-parquet-pushdown"]{Projection and predicate pushdown}

A scan reads only what its plan needs. @racket[explain] shows the plan:
written, the filter and the selection sit above the scan; optimised, both
move into it, so Polars reads two of the 19 columns (@tt{PROJECT}) and
applies the filter as it reads (@tt{SELECTION}), skipping any row group
whose statistics rule it out.

@examples[#:eval ev #:label #f
(define late
  (~> (scan-parquet "flights.parquet")
      (filter (> (col "dep_delay") 20))
      (select "carrier" "dep_delay")))
(displayln (explain late #:optimized #f))
(displayln (explain late))
(collect late)
]

@section[#:tag "io-parquet-options"]{Options}

Upstream documents the readers' and the writer's options on their reference
pages; each keyword here keeps Python's name. @racket[#:columns],
@racket[#:n-rows] and @racket[#:row-index-name] frame what
@racket[read-parquet] returns; @racket[#:compression],
@racket[#:compression-level], @racket[#:statistics] and
@racket[#:row-group-size] set how @racket[write-parquet] lays the file out.

@examples[#:eval ev #:label #f
(read-parquet "flights.parquet" #:columns '("row" "carrier" "dep_delay") #:n-rows 3
              #:row-index-name "row")
(write-parquet flights (build-path dir "flights.parquet")
               #:compression 'gzip #:compression-level 9 #:statistics 'full
               #:row-group-size 50)
(shape (read-parquet (build-path dir "flights.parquet")))
]

API gaps: no @tt{schema}, @tt{extra_columns} or @tt{metadata} (#197).

@examples[#:eval ev #:hidden
(delete-directory/files dir)
]

@(close-eval ev)
