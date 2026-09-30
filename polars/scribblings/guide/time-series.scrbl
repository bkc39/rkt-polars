#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define-runtime-path data-dir "../data")
@(define ev (make-polars-eval #:directory data-dir))

@title[#:tag "time-series" #:style 'toc]{Time series}

@see-reference["ref-temporal-values"]{how gregor values map to the temporal dtypes}

@local-table-of-contents[]

The examples read upstream's @filepath{apple_stock.csv}, a hundred closing
prices of Apple stock from 1981 to 2014.

API gaps: no @tt{group_by_dynamic}, @tt{rolling} or @tt{upsample}, so
upstream's Grouping and Resampling pages have no counterpart; no time zones
(its Time zones page).

@section[#:tag "ts-parsing"]{Parsing}

Polars has four temporal dtypes, and each crosses into Racket as a gregor
value:

@itemlist[
  @item{@racket['date]: days since the UNIX epoch, as a 32-bit integer; a
    gregor @tt{date}.}
  @item{@racket['(datetime unit #f)]: a 64-bit count of milliseconds,
    microseconds or nanoseconds since the epoch; a gregor @tt{datetime}.}
  @item{@racket['(duration unit)]: a time delta; a gregor @tt{period}.}
  @item{@racket['time]: nanoseconds since midnight; a gregor @tt{time}.}]

@subsection[#:tag "ts-parsing-file"]{Parsing dates from a file}

@racket[#:try-parse-dates] parses dates and times as a CSV file is read:

@examples[#:eval ev #:label #f
(read-csv "apple_stock.csv" #:try-parse-dates #t)
]

Inference reads the first @racket[#:infer-schema-length] rows, 100 by
default. A binary format such as Parquet carries its schema, which is used
as it is.

@subsection[#:tag "ts-parsing-cast"]{Casting strings to dates}

@racket[str->date] parses a string column with a chrono format:

@examples[#:eval ev #:label #f
(define df
  (~> (read-csv "apple_stock.csv")
      (with-columns (str->date "Date" #:format "%Y-%m-%d"))))
df
]

@subsection[#:tag "ts-parsing-extract"]{Extracting date features}

@racket[dt-year] and the other @tt{dt-} operations read a field of a date
column:

@examples[#:eval ev #:label #f
(with-columns df (~> (col "Date") dt-year (alias "year")))
]

@subsection[#:tag "ts-parsing-offsets"]{Mixed offsets}

API gap: no time zones. @racket[str->datetime] drops an offset parsed with
@litchar{%z}, where Python converts to UTC, and there is no
@tt{dt.convert_time_zone}.

@subsection[#:tag "ts-parsing-racket"]{Dates from Racket values}

A series of gregor dates is a date column, and a date column's values come
back as gregor dates:

@examples[#:eval ev #:label #f
(define closes (series (list (date 1995 10 16) (date 1995 11 1)) #:name "Date"))
closes
(series->list closes)
]

@section[#:tag "ts-filtering"]{Filtering}

A date column filters like any other. Its comparisons take gregor values,
as Python's take @tt{date}, @tt{datetime} and @tt{timedelta}:

@examples[#:eval ev #:label #f
(define stock (read-csv "apple_stock.csv" #:try-parse-dates #t))
stock
]

@subsection[#:tag "ts-filtering-single"]{Filtering by single dates}

@examples[#:eval ev #:label #f
(filter stock (= (col "Date") (datetime 1995 10 16)))
]

A gregor @tt{datetime} compares with a date column as midnight of that day,
and a gregor @tt{date} works as well.

@subsection[#:tag "ts-filtering-range"]{Filtering by a date range}

@examples[#:eval ev #:label #f
(filter stock (is-between "Date" (datetime 1995 7 1) (datetime 1995 11 1)))
]

@subsection[#:tag "ts-filtering-negative"]{Filtering with negative dates}

Polars parses and stores dates before year 1. Python's @tt{datetime} cannot
hold them, so upstream filters on the year; gregor can, so a Racket date
compares directly too:

@examples[#:eval ev #:label #f
(define negative-dates
  (~> (dataframe (list (series '("-1300-05-23" "-1400-03-02") #:name "ts")
                       (series '(3 4) #:name "values")))
      (with-columns (str->date "ts"))))
(filter negative-dates (< (dt-year "ts") -1300))
(filter negative-dates (= (col "ts") (date -1300 5 23)))
]

@(close-eval ev)
