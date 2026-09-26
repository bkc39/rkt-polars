#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define-runtime-path data-dir "../data")
@(define ev (make-polars-eval #:directory data-dir))

@title[#:tag "io" #:style 'toc]{IO}

@see-reference["ref-fluent"]{@racket[read-csv], @racket[scan-csv] and the other readers}

@local-table-of-contents[]

@section[#:tag "io-csv"]{CSV}

@subsection[#:tag "io-csv-read-write"]{Read & write}

@examples[#:eval ev #:hidden
(define path (build-path (find-system-path 'temp-dir) "polars-guide-path.csv"))
]

Writing a CSV file uses @racket[write-csv], and reading one should look
familiar:

@examples[#:eval ev #:label #f
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-csv df path)
(read-csv path)
]

@subsection[#:tag "io-csv-scan"]{Scan}

Polars can also @emph{scan} a CSV input. Scanning delays the actual parsing
of the file and returns a @tech{lazyframe}, a lazy computation holder;
@racket[collect] runs it. See @secref["concepts-lazy-api"] for why that is
desirable.

@examples[#:eval ev #:label #f
(scan-csv path)
(collect (scan-csv path))
]

@subsection[#:tag "io-csv-options"]{Reading options}

Upstream documents @tt{read_csv}'s options on its reference page; here they
are with their Racket spellings. Each keyword keeps Python's name and works
the same on @racket[read-csv] and @racket[scan-csv]. The file,
@filepath{flights.tsv}, is 102 rows of nycflights13, tab-separated, with
@litchar{NA} for a missing value.

@bold{Separator.} Read with the default comma, a tab-separated file is one
column whose name is the whole header line. Python's @tt{read_csv} returns
that column; @racket[read-csv] is stricter and raises, naming the separator
to pass. Passing any @racket[#:separator], even @racket[#\,], turns the check
off, and @racket[scan-csv] does not check.

@examples[#:eval ev #:label #f
(eval:error (read-csv "flights.tsv"))
(shape (read-csv "flights.tsv" #:separator #\,))
]

@bold{Missing values.} Types are inferred from the first 100 rows, and the
first @litchar{NA} comes later. @racket[#:null-values] takes one marker or a
list of them:

@examples[#:eval ev #:label #f
(eval:error (read-csv "flights.tsv" #:separator #\tab))
(define flights (read-csv "flights.tsv" #:separator #\tab #:null-values "NA"))
(~> flights (select "dep_delay" "arr_delay") (tail 3))
(~> (read-csv "flights.tsv" #:separator #\tab #:null-values '("NA" "-"))
    (ref #:columns "air_time")
    null-count)
]

@bold{Types.} @racket[#:schema-overrides] fixes a column's type, in any
spelling @racket[series] accepts; @racket[#:infer-schema-length] sets how
many rows inference reads (@racket[#f] for all of them, @racket[0] for
strings throughout); @racket[#:ignore-errors] reads what does not parse as
null; @racket[#:try-parse-dates] reads ISO dates and datetimes as such.

@examples[#:eval ev #:label #f
(~> (read-csv "flights.tsv" #:separator #\tab #:null-values "NA"
              #:schema-overrides '(("dep_delay" . f64) ("flight" . int32)))
    (select "dep_delay" "flight")
    (tail 2))
(~> (read-csv "flights.tsv" #:separator #\tab #:infer-schema-length #f)
    (ref #:columns "dep_delay")
    dtype)
(~> (read-csv "flights.tsv" #:separator #\tab #:ignore-errors #t)
    (ref #:columns "dep_delay")
    null-count)
(~> (read-csv "flights.tsv" #:separator #\tab #:null-values "NA"
              #:try-parse-dates #t)
    (select "time_hour")
    (head 2))
]

@bold{Layout.} @filepath{notes.csv} starts with a comment line, separates
fields with @litchar{;} and quotes a field that holds one with @litchar{'};
@filepath{latin1.csv} is not UTF-8. @racket[#:has-header], @racket[#:skip-rows]
and @racket[#:n-rows] frame the rows to read.

@examples[#:eval ev #:label #f
(read-csv "notes.csv" #:separator #\; #:comment-prefix "#" #:quote-char #\')
(read-csv "latin1.csv" #:encoding 'utf8-lossy)
(read-csv "parts/part-1.csv" #:has-header #f #:skip-rows 1 #:n-rows 1)
]

API gaps: @tt{null_values} takes no per-column mapping (#101); no
@tt{columns}, @tt{new_columns}, @tt{eol_char}, @tt{row_index_name},
@tt{truncate_ragged_lines} or @tt{decimal_comma}. A @racket['time] override is
rejected, because Polars 0.41.3 cannot parse one from CSV.

@section[#:tag "io-multiple"]{Multiple files}

Polars can deal with multiple files differently depending on your needs and
memory strain. Let's create some files to give us some context:

@examples[#:eval ev #:hidden
(require racket/file file/glob)
(define dir (make-temporary-directory "polars-guide-~a"))
]

@examples[#:eval ev #:label #f
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "ham" "spam") #:name "bar"))))
(for ([i (in-range 5)])
  (write-csv df (build-path dir (format "my_many_files_~a.csv" i))))
]

@subsection[#:tag "io-multiple-single"]{Reading into a single dataframe}

To read multiple files into a single @tech{dataframe}, use a glob pattern.
The files are read separately and stacked in filename order.

@examples[#:eval ev #:label #f
(read-csv (build-path dir "my_many_files_*.csv"))
]

@racket[read-parquet] and @racket[scan-parquet] take a pattern the same way:

@examples[#:eval ev #:label #f
(for ([i (in-range 2)])
  (write-parquet df (build-path dir (format "my_many_files_~a.parquet" i))))
(height (read-parquet (build-path dir "my_many_files_*.parquet")))
]

API gap: no @tt{show_graph}, so the query plan cannot be drawn.

@subsection[#:tag "io-multiple-parallel"]{Reading and processing in parallel}

If your files don't have to be in a single table, build a query plan for
each file.

@examples[#:eval ev #:label #f
(for/list ([file (sort (glob (build-path dir "my_many_files_*.csv")) path<?)])
  (~> (scan-csv file)
      (group-by "bar")
      (agg (alias (count "foo") "len") (sum "foo"))
      (sort "bar")
      collect))
]

API gaps: no @tt{collect_all}, so the plans run one after another rather
than together on the Polars thread pool; no @tt{pl.len()}, so a column's
@racket[count] stands in.

@(close-eval ev)
