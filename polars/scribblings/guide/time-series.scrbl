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
upstream's Grouping and Resampling pages have no counterpart.

@section[#:tag "ts-parsing"]{Parsing}

Polars has four temporal dtypes, and each crosses into Racket as a gregor
value:

@itemlist[
  @item{@racket['date]: days since the UNIX epoch, as a 32-bit integer; a
    gregor @tt{date}.}
  @item{@racket['(datetime unit #f)]: a 64-bit count of milliseconds,
    microseconds or nanoseconds since the epoch; a gregor @tt{datetime}.
    With a time zone, @racket['(datetime unit "Zone/Name")], a gregor
    @tt{moment} (@secref["ts-time-zones"]).}
  @item{@racket['(duration unit)]: a time delta; a gregor @tt{period}.}
  @item{@racket['time]: nanoseconds since midnight; a gregor @tt{time}.}]

@subsection[#:tag "ts-parsing-file"]{Parsing dates from a file}

Reading a CSV file with its dates parsed, @racket[#:try-parse-dates], is
covered with the other reading options in @secref["io-csv-dates"].

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

Datetimes with mixed UTC offsets, as on either side of a daylight-saving
change, parse to UTC. Pass @racket[str->datetime] a target zone with
@racket[#:time-zone], or convert after parsing with
@racket[dt-convert-time-zone]:

@examples[#:eval ev #:label #f
(define mixed
  (dataframe (list (series '("2021-03-27T00:00:00+0100" "2021-03-28T00:00:00+0100"
                             "2021-03-29T00:00:00+0200" "2021-03-30T00:00:00+0200")
                           #:name "data"))))
(define mixed-parsed
  (~> mixed
      (select (~> (str->datetime "data" #:format "%Y-%m-%dT%H:%M:%S%z")
                  (dt-convert-time-zone "Europe/Brussels")))
      (ref "data")))
mixed-parsed
]

@subsection[#:tag "ts-parsing-racket"]{Dates from Racket values}

A series of gregor dates is a date column, and a date column's values come
back as gregor dates:

@examples[#:eval ev #:label #f
(define closes (series (list (date 1995 10 16) (date 1995 11 1)) #:name "Date"))
closes
(series->list closes)
]

gregor datetimes make a microsecond column, as Python's @tt{datetime}s do.
gregor's reach the nanosecond: a value with a sub-microsecond part makes the
column nanoseconds when a nanosecond column, which spans 1677 to 2262, holds
every value, and otherwise the part is floored:

@examples[#:eval ev #:label #f
(series (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1995 11 1)) #:name "precise")
(series (list (datetime 1995 10 16 9 30 0 123456789) (datetime 1600 1 1)) #:name "wide")
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

@section[#:tag "ts-time-zones"]{Time zones}

Avoid time zones when you can. A datetime column has none (it is naive),
@racket["UTC"], or an area/location zone from the tz database such as
@racket["Asia/Kathmandu"]; its dtype is @racket['(datetime unit "Zone/Name")].
Fixed offsets such as @tt{+02:00} are better avoided: Polars keeps one as
@racket["Etc/GMT-2"], which knows no daylight saving. A column has one zone,
so data with several offsets parses to UTC (@secref["ts-parsing-offsets"]).

@racket[dt-convert-time-zone] converts from one zone to another, keeping
each instant; @racket[dt-replace-time-zone] sets, changes or, given
@racket[#f], unsets the zone, keeping each wall-clock time:

@examples[#:eval ev #:label #f
(define ts '("2021-03-27 03:00" "2021-03-28 03:00"))
(define tz-naive
  (~> (dataframe (list (series ts #:name "tz_naive")))
      (select (str->datetime "tz_naive"))
      (ref "tz_naive")))
(define tz-aware (~> tz-naive (dt-replace-time-zone "UTC") (rename "tz_aware")))
(define time-zones-df (dataframe (list tz-naive tz-aware)))
time-zones-df
(select time-zones-df
        (~> (col "tz_aware") (dt-replace-time-zone "Europe/Brussels")
            (alias "replace time zone"))
        (~> (col "tz_aware") (dt-convert-time-zone "Asia/Kathmandu")
            (alias "convert time zone"))
        (~> (col "tz_aware") (dt-replace-time-zone #f) (alias "unset time zone")))
]

@subsection[#:tag "ts-time-zones-racket"]{Zoned values from Racket}

A gregor @tt{moment} is an instant in a zone, as Python's aware
@tt{datetime} is, and a zoned column's values come back as moments in its
zone. A list takes the zone of its first moment, as Python's does; a fixed
offset gives UTC:

@examples[#:eval ev #:label #f
(define landings
  (series (list (moment 2021 3 27 9 #:tz "Europe/Brussels")
                (moment 2021 3 28 9 #:tz "Europe/Brussels")
                (moment 2021 3 27 18 #:tz "Asia/Kathmandu"))
          #:name "landed"))
landings
(series->list landings)
(dtype (series (list (moment 2021 3 27 9 #:tz 3600))))
]

A moment read back carries Polars' offset, from chrono-tz's tz database.
gregor reads the system's zoneinfo, which can disagree before 1970 or after
2037, so a moment built there can name another instant than Polars would
(@secref["ref-temporal-values"]).

@(close-eval ev)
