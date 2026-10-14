#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path
          (for-label (only-in plot/pict plot)
                     (only-in plot density)))

@(define-runtime-path data-dir "../data")
@(define ev (make-polars-eval #:directory data-dir))

@title[#:tag "nycflights" #:style 'toc]{Case study: nycflights}

@see-reference["ref-fluent"]{the verbs used here, and @secref["ref-series"] and
@secref["ref-dataframes"] for the conversions, @racket[define-enum],
@racket[describe] and the accessors}

@hyperlink["https://aliquote.org/post/racket-data-frames/"]{Data frames for Racket}
(aliquote.org, July 2023) loads the 29 MB @tt{nycflights.tsv}, every flight
that left New York in 2013, with three Racket libraries, then walks
@tt{tabular-asa} through a select, a distinct, a group-by and a density plot.
Along the way it lists what the libraries cannot do: read another separator,
keep categorical variables, parse dates, describe a string column usefully.
This chapter replays each step in rkt-polars, the post's code first, and
answers each complaint.

@local-table-of-contents[]

@section[#:tag "nycflights-data"]{The data}

The post's file is the @tt{flights} table of the R package
@hyperlink["https://cran.r-project.org/package=nycflights13"]{nycflights13}
(Hadley Wickham, released under CC0; the data come from the US Bureau of
Transportation Statistics), as the TSV at
@tt{https://www.travishinkelman.com/data/nycflights.tsv}: 336,776 rows ×
19 columns, @litchar{NA} for a missing value. The examples here run while the
manual builds, with no network, so they read @filepath{nycflights-sample.tsv},
which ships with the package: the header and the 5,434 flights on the first
day of January, March, May, July, September and November, their lines
unchanged (492 KB).

@commandline{awk -F'\t' 'NR == 1 || ($3 == 1 && $2 % 2 == 1)' nycflights.tsv}

Counts below are the sample's; the prose gives the full file's, from
@tt{nix run .#bench} in the repository. The bench fetches the post's file,
checks its hash, checks the post's steps and complaints on it (the
scoreboard), and times the operations against Python polars; its ratio table
closes the chapter.

@section[#:tag "nycflights-require"]{Requiring polars}

@racket[(require polars)] shadows @racketmodname[racket/base]'s arithmetic,
comparison and logic operators, @racket[filter], @racket[sort],
@racket[min], @racket[max], @racket[round] and a few more
(@secref["fluent-shadowing"] lists them). Each falls back to its
@racketmodname[racket/base] meaning on plain values:

@examples[#:eval ev #:label #f
(filter even? '(1 2 3 4))
(sort '(3 1 2) <)
(max 3 7)
]

To keep the two apart, require polars under a prefix:

@examples[#:eval ev #:label #f
(require (prefix-in pl: polars))
(pl:~> (pl:series '(3 1 2)) pl:sort pl:series->list)
]

@racketmodname[plot/pict], which draws the plot below, shares no name with
polars.

@section[#:tag "nycflights-load"]{Loading the file}

The post times three readers. @tt{data-frame} takes no other separator, so
the post converts the TSV to CSV for it, and @tt{tabular-asa} reads the same
copy:

@racketblock[
(code:comment "csv-reading, from the URL: cpu 4366 ms, real 9121 ms")
(time (define data (csv->list file)) (void))
(code:comment "data-frame: 3708 ms")
(time (define data (df-read/csv file #:headers? #t)) (void))
(code:comment "tabular-asa: 7142 ms")
(time (define data (call-with-input-file "nycflights.csv" table-read/csv))
      (void))
]

API gap: @racket[read-csv] reads a local file, not a URL as the post's first
reader does and Python's @tt{read_csv} can (#159); fetch the file first.

@racket[read-csv] reads the TSV as it is: @racket[#:separator] names the
tab, and @racket[#:null-values] the @litchar{NA} marker, which becomes a null
in an integer column.

@examples[#:eval ev #:label #f
(define flights
  (read-csv "nycflights-sample.tsv" #:separator #\tab #:null-values "NA"))
flights
]

Without @racket[#:null-values], the first rows infer integers and the first
@litchar{NA} fails the read; the error says what to pass:

@examples[#:eval ev #:label #f
(eval:error (read-csv "nycflights-sample.tsv" #:separator #\tab))
]

@section[#:tag "nycflights-select"]{Selecting columns}

@racketblock[
(define subset (table-cut data '(distance dep_delay dest)))
(display-table subset)
]

@examples[#:eval ev #:label #f
(define subset (select flights "distance" "dep_delay" "dest"))
subset
]

A frame prints its first and last rows, as @tt{display-table} does; a missing
delay prints as @tt{null} where @tt{tabular-asa} has @racket[#f].

@section[#:tag "nycflights-distinct"]{Distinct destinations}

@racketblock[
(table-shape (table-distinct subset '(dest)))
(code:comment "=> 105 3")
]

@examples[#:eval ev #:label #f
(~> subset (select "dest") unique height)
(~> subset (select (n-unique "dest")))
]

The sample has 96 of the 105 destinations. API gap: @racket[unique] takes no
subset of columns (#134), so it cannot keep the other columns as
@tt{table-distinct} does; each group's @racket[first] row gives the post's
shape:

@examples[#:eval ev #:label #f
(~> subset (group-by "dest") (agg (first "distance") (first "dep_delay")) shape)
]

@section[#:tag "nycflights-group-by"]{Counting and averaging by destination}

@racketblock[
(define grouped-data
  (group-count (table-groupby (table-cut subset '(dest dep_delay)) '(dest))))
]

@examples[#:eval ev #:label #f
(define by-dest
  (~> subset
      (group-by "dest")
      (agg (alias (count "dep_delay") "departed")
           (alias (mean "dep_delay") "mean_delay"))
      (sort "dest")))
by-dest
]

@racket[count], like @tt{group-count}, skips missing values: on the full file
ATL has 16,898, the post's figure, of 17,215 flights, and a mean delay of
12.5 minutes. The groups come back in no fixed order, as in Python; sort them
to print.

@section[#:tag "nycflights-plot"]{Delays into Racket, and a density plot}

@racketblock[
(require plot)
(define xs (for/list ([x (table-column grouped-data 'dep_delay)]) x))
(plot (density xs) #:x-label "Departure delay" #:y-label "Density"
      #:out-file "/tmp/plot.png")
]

The post's @racket[xs] is @tt{grouped-data}'s @tt{dep_delay} column, which
@tt{group-count} has replaced by each destination's count; here @racket[xs]
is the delays themselves. @racket[series->list] copies a column into a list
in one foreign call (the full file's 328,521 delays take about 3 ms), after
@racket[drop-nulls] removes the cancelled flights, which have no delay:

@examples[#:eval ev #:label #f
(define xs (~> flights (ref "dep_delay") drop-nulls series->list))
(length xs)
(require plot/pict)
(plot (density xs) #:x-max 180
      #:x-label "Departure delay (minutes)" #:y-label "Density")
]

The view stops at three hours; the sample's longest delay is 853 minutes.
Plotting is client code, and a @tt{df.plot} namespace is a non-goal (#121,
@secref["interop-visualization"]): take the columns out with
@racket[series->list] or @racket[series->vector] and hand them to
@racketmodname[plot]. An @racket[f64vector] from @racket[series->f64vector] is
not a sequence, so a renderer such as @racket[density] refuses it;
@racket[f64vector->list] converts it. The plot is drawn while the manual
builds, so @tt{plot-lib}, @tt{plot-gui-lib} and @tt{plot-doc} are among the
package's @tt{build-deps}, which a source install pulls in and a binary
package drops. They are not in its @tt{deps}: @racket[(require polars)] loads
no plotting code.

@section[#:tag "nycflights-filter"]{Filtering}

The scoreboard adds two steps the post leaves out, both where missing values
matter. A null delay is not greater than 60, so keeping the flights more than
an hour late drops the cancelled ones too (26,581 flights remain on the full
file):

@examples[#:eval ev #:label #f
(~> flights (filter (> (col "dep_delay") 60)) height)
]

@section[#:tag "nycflights-top-delays"]{The largest delays}

A descending sort puts nulls first, as Python's does; @racket[#:nulls-last]
moves them to the end. On the full file the five largest delays are 1301,
1137, 1126, 1014 and 1005 minutes.

@examples[#:eval ev #:label #f
(~> flights (sort "dep_delay" #:descending #t) (select "dep_delay") (head 3))
(~> flights
    (sort "dep_delay" #:descending #t #:nulls-last #t)
    (select "dep_delay" "carrier" "dest")
    (head 5))
]

@section[#:tag "nycflights-separator"]{Other separators}

The post converts the TSV to CSV for @tt{data-frame}. @racket[#:separator]
takes any ASCII character but a line break or the quote character. Read with the default comma, the TSV is one
column named after the whole header line, which Python's @tt{read_csv}
returns; @racket[read-csv] raises instead and names the separator to pass:

@examples[#:eval ev #:label #f
(eval:error (read-csv "nycflights-sample.tsv"))
]

See @secref["io-csv-options"] for the other reading options.

@section[#:tag "nycflights-categorical"]{Categorical variables}

Neither @tt{data-frame} nor @tt{tabular-asa} has a categorical type, short of
recoding the strings as numbers, which the post's author once did. A @racket['categorical] column stores each
string once and reads back as symbols. When the categories are known up
front, as the three New York airports in @tt{origin} are, @racket[define-enum]
declares them, in order, as an Enum:

@examples[#:eval ev #:label #f
(define-enum nyc-airport EWR JFK LGA)
(define coded
  (with-columns flights
    (cast "carrier" 'categorical)
    (cast "dest" 'categorical)
    (cast "origin" nyc-airport)))
(for/list ([name '("carrier" "dest" "origin")])
  (dtype (ref coded name)))
(~> coded (ref "dest") (head 3) series->list)
(~> coded (filter (= (col "origin") 'JFK)) height)
(~> coded
    (group-by "origin")
    (agg (alias (mean "dep_delay") "mean_delay"))
    (sort "origin"))
(eval:error (cast (series '(EWR TEB)) nyc-airport))
]

@racket[read-csv]'s @racket[#:schema-overrides] loads a column as
categorical directly. API gap: not as an Enum (#133). See
@secref["expressions-categoricals"].

@section[#:tag "nycflights-describe"]{Describing strings and datetimes}

The post finds @tt{df-describe} “pretty useless” on @tt{carrier}, @tt{dest}
and @tt{time_hour}, which @tt{data-frame} keeps as strings. @racket[describe] gives a
string column its count, null count, minimum and maximum; parsed as a
datetime, @tt{time_hour} also gets a mean and quartiles:

@examples[#:eval ev #:label #f
(~> flights
    (with-columns (str->datetime "time_hour"))
    (select "carrier" "dest" "time_hour")
    describe)
]

@racket[read-csv]'s @racket[#:try-parse-dates] parses @tt{time_hour} at load
instead. A categorical column gets only the two counts, as in Python; its
useful summary is a count per category:

@examples[#:eval ev #:label #f
(~> coded
    (group-by "carrier")
    (agg (alias (count "carrier") "flights"))
    (sort "flights" #:descending #t)
    (head 5))
]

@section[#:tag "nycflights-performance"]{Performance}

The post's loads take 3.7 s (@tt{data-frame}) and 7.1 s (@tt{tabular-asa})
under Racket 8.6 CS, on its author's machine in 2023. On the bench's host,
rkt-polars loads the post's TSV in 21.5 ms and Python polars in 20.8 ms. The
two pairs come from different machines, so compare within each pair, not
across.

The bench's ratio table, measured on 2026-09-29 (not a live timing):
rkt-polars as of the categoricals change (#128; polars crate 0.55.2,
Racket 9.3) against Python polars 1.42.1, on the full file, on an Intel Core
i9-9900K (8 cores, 16 threads) at a one-minute load average of 1.7--2.8
(five-minute 6.8--7.0). Each time is the mean of two rounds, each round the
median of 5 runs after a warm-up; each ratio is the mean of the two rounds'
ratios, which the bench takes before rounding. A ratio below 1 is faster than
Python.

@tabular[#:style 'boxed
         #:sep @hspace[2]
         #:column-properties '(left right right right)
         #:row-properties '(bottom-border ())
 (list (list @bold{operation} @bold{rkt-polars ms} @bold{Python ms} @bold{ratio})
       (list "load TSV"                "21.5" "20.8" "1.04")
       (list "load CSV"                "21.3" "20.9" "1.02")
       (list "lazy scan + collect"     "40.2" "38.8" "1.04")
       (list "select"                  "0.1"  "1.6"  "0.08")
       (list "distinct"                "3.7"  "5.2"  "0.72")
       (list "group-by count + mean"   "4.7"  "10.8" "0.44")
       (list "filter"                  "4.9"  "4.6"  "1.07")
       (list "sort + top 5"            "28.4" "28.4" "1.00")
       (list "describe"                "20.3" "18.9" "1.07")
       (list "column → list"           "3.2"  "4.2"  "0.81")
       (list "dataframe → f64 matrix"  "30.1" "19.0" "1.59")
       (list "cast 3 to categorical"   "5.3"  "4.8"  "1.11")
       (list "group-by on categorical" "2.8"  "9.3"  "0.30")
       (list "categorical → list"      "4.2"  "12.1" "0.35"))]

The f64 matrix is the one operation over 1.2×; #115 tracks it.
