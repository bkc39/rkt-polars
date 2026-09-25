#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define ev (make-polars-eval))
@(define-runtime-path iris-csv-path "iris.csv")
@(ev `(define iris-csv ,(path->string iris-csv-path)))

@title[#:tag "interop" #:style 'toc]{Interoperability}

@see-reference["ref-series-convert"]{every conversion used here}

Handing Polars data to Racket code that is not Polars: a loop, a numeric
routine, a foreign solver, a plot. The chapter mirrors upstream's
@hyperlink["https://docs.pola.rs/user-guide/misc/arrow/"]{Arrow producer/consumer}
and @hyperlink["https://docs.pola.rs/user-guide/misc/visualization/"]{Visualization}
pages, with the Python export calls those pages lean on: @tt{Series.to_list},
@tt{Series.to_numpy}, @tt{DataFrame.to_dict} and @tt{DataFrame.to_numpy}.

@local-table-of-contents[]

@section[#:tag "interop-values"]{Series to Racket values}

@racket[series->list] is @tt{Series.to_list()}, and @racket[series->vector] its
vector twin. The column is copied out a block of rows at a time, not one
foreign call per element. A null comes out as @racket[polars-null], or as the
@racket[#:null] value.

@examples[#:eval ev #:label #f
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series '("ham" "spam" "jam") #:name "bar"))))
(~> df (ref "foo") series->list)
(~> df (ref "bar") series->vector)
(define gappy (series (list 1 polars-null 3) #:name "value"))
(series->list gappy)
(series->list gappy #:null 0)
]

Every element is what @racket[ref] returns: exact integers, flonums, booleans,
strings, and gregor values for the temporal dtypes.

@examples[#:eval ev #:label #f
(define people
  (~> (dataframe
       (list (series '("Alice Archer" "Ben Brown") #:name "name")
             (series (list (datetime 1997 1 10 8 30 0) (datetime 1985 2 15 17 0 0))
                     #:name "birthdate")
             (series '(57.9 72.5) #:name "weight")
             (series '(#t #f) #:name "parent")))
      (with-columns (alias (cast "birthdate" 'date) "birthday")
                    (alias (cast "birthdate" 'time) "clock"))))
(for/list ([name (column-names people)])
  (~> people (ref name) series->list))
]

API gaps: datetimes come out floored to the whole second, where
@tt{to_list} keeps microseconds; a @racket['binary] column has no Racket value.

@section[#:tag "interop-iterating"]{Iterating}

A series is a sequence, so @racket[for] walks it directly, as Python's
@tt{for x in s} does; @racket[in-series] adds @racket[#:null]. Rows are
converted a block at a time, so a loop that stops early converts little more
than it reads.

@examples[#:eval ev #:label #f
(for/list ([word (ref df "bar")]) (string-upcase word))
(for/sum ([v (in-series gappy #:null 0)]) v)
(for/first ([v (in-series (series (build-list 1000000 values)))]
            #:when (> v 41))
  v)
]

@section[#:tag "interop-columns"]{Columns as Racket data}

@racket[dataframe->columns] is @tt{DataFrame.to_dict(as_series=False)}: each
column name paired with a vector of its values, in column order or in the
order of @racket[#:columns].

@examples[#:eval ev #:label #f
(dataframe->columns df)
(dataframe->columns people #:columns '("weight" "name"))
(cdr (assoc "bar" (dataframe->columns df)))
]

@section[#:tag "interop-numeric"]{Numeric buffers}

@racket[series->f64vector] is @tt{Series.to_numpy()} for a numeric column: an
@racket[f64vector] from @racketmodname[ffi/vector], the type foreign code
takes. Integers and booleans are cast while copying. A null becomes
@racket[+nan.0] or the @racket[#:null] value, and @racket['error] refuses
nulls.

@examples[#:eval ev #:label #f
(require ffi/vector)
(~> df (ref "foo") series->f64vector f64vector->list)
(f64vector->list (series->f64vector gappy))
(f64vector->list (series->f64vector gappy #:null -1))
(eval:error (series->f64vector gappy #:null 'error))
]

@racket[dataframe->f64vector] is @tt{DataFrame.to_numpy()}: one buffer for the
selected columns, returned with its row and column counts. It is column-major
by default (@racket['fortran], numpy's @tt{order="F"}) and row-major with
@racket['c].

@examples[#:eval ev #:label #f
(define xy (dataframe (list (series (list 1 2 polars-null) #:name "a")
                            (series '(0.5 1.5 2.5) #:name "b"))))
(define-values (m nrows ncols) (dataframe->f64vector xy))
(list nrows ncols (f64vector->list m))
(define-values (m/c rows/c cols/c) (dataframe->f64vector xy #:order 'c))
(f64vector->list m/c)
(define-values (b rows/b cols/b) (dataframe->f64vector xy #:columns '("b") #:null 'error))
(f64vector->list b)
(eval:error (dataframe->f64vector xy #:null 'error))
(eval:error (dataframe->f64vector df))
]

A null becomes NaN here, as in @tt{to_numpy}, although Polars keeps the two
apart (upstream's
@hyperlink["https://docs.pola.rs/user-guide/expressions/missing-data/"]{Missing data}
page). Pass @racket['error] where a NaN would be taken for data.

API gaps: no Arrow export (@tt{to_arrow}, the Arrow C Data Interface); no
integer native vectors; a string or temporal column is refused where
@tt{to_numpy} builds an object or @tt{datetime64} array. The buffer is
garbage-collected memory that Racket CS may move, so hand it only to a foreign
call that is not @racket[#:blocking?].

@section[#:tag "interop-visualization"]{Data for a plot}

Upstream's Visualization page hands two iris columns to a plotting library.
The @tt{plot} library's @tt{points} renderer takes a list of vectors, which is
two conversions away.

@examples[#:eval ev #:label #f
(define iris (read-csv iris-csv))
(define sepals
  (map vector
       (~> iris (ref "sepal_width") series->list)
       (~> iris (ref "sepal_length") series->list)))
(length sepals)
(for/list ([p sepals] [_ 3]) p)
]

@tt{(plot (points sepals))} draws the scatter. @tt{plot} is not a dependency
of this package, so the manual does not render it.

API gap: no plotting namespace (@tt{df.plot}, hvPlot).
