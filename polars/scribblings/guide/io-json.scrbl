#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define-runtime-path data-dir "../data")
@(define ev (make-polars-eval #:directory data-dir))

@title[#:tag "io-json"]{JSON files}

@see-reference["ref-fluent"]{@racket[read-json], @racket[read-ndjson] and
the other JSON readers and writers}

Polars can read and write both standard JSON and newline-delimited JSON
(NDJSON).

@examples[#:eval ev #:hidden
(require racket/file)
(define dir (make-temporary-directory "polars-guide-~a"))
(define path (build-path dir "path.json"))
(define nd-path (build-path dir "path.ndjson"))
]

@section[#:tag "io-json-read"]{Read}

@subsection[#:tag "io-json-read-json"]{JSON}

Reading a JSON file should look familiar:

@examples[#:eval ev #:label #f
(read-json "stations.json")
]

@subsection[#:tag "io-json-read-ndjson"]{Newline Delimited JSON}

JSON objects that are delimited by newlines can be read into Polars in a much
more performant way than standard JSON.

Polars can read an NDJSON file into a @tech{dataframe} using
@racket[read-ndjson]:

@examples[#:eval ev #:label #f
(read-ndjson "stations.ndjson")
]

@section[#:tag "io-json-write"]{Write}

@examples[#:eval ev #:label #f
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-json df path)
(file->string path)
(read-json path)
(write-ndjson df nd-path)
(file->string nd-path)
(read-ndjson nd-path)
]

Racket's @racketmodname[json] library also provides @racket[read-json] and
@racket[write-json], so @racket[(require polars json)] fails with
``identifier already required''. Rename @racketmodname[json]'s pair with
@racket[(require polars (prefix-in js: json))], or leave it out with
@racket[(require polars (except-in json read-json write-json))].

@section[#:tag "io-json-scan"]{Scan}

Polars allows you to @emph{scan} an NDJSON input. Scanning delays the actual
parsing of the file and instead returns a lazy computation holder called a
@tech{lazyframe}.

@examples[#:eval ev #:label #f
(scan-ndjson "stations.ndjson")
(~> (scan-ndjson "stations.ndjson")
    (filter (> (col "reading") 3))
    collect)
]

@section[#:tag "io-json-options"]{Reading options}

Upstream documents @tt{read_json}'s and @tt{read_ndjson}'s options on its
reference pages; here they are with their Racket spellings.
@filepath{stations.json} and @filepath{stations.ndjson} hold the same
objects: a @litchar{reading} that starts as an integer, and a
@litchar{note} key that only the last object carries.

@bold{Types.} @racket[#:schema] gives the columns and their types outright;
@racket[#:schema-overrides] changes the types of some inferred columns.
Either reads an ISO date string as a date.

@examples[#:eval ev #:label #f
(read-json "stations.json"
           #:schema '(("day" . date) ("station" . categorical) ("reading" . f32)))
(~> (read-json "stations.json" #:schema-overrides '(("day" . date)))
    (select "day" "reading"))
]

@bold{Inference.} Types are inferred from the first 100 objects;
@racket[#:infer-schema-length] changes that, and @racket[#f] reads them all.
A key that first appears later is an error:

@examples[#:eval ev #:label #f
(eval:error (read-json "stations.json" #:infer-schema-length 1))
(shape (read-json "stations.json" #:infer-schema-length #f))
]

@racket[read-ndjson] and @racket[scan-ndjson] take the same three keywords,
but leave a late key out, and @racket[#:ignore-errors] reads a value that
does not parse as null:

@examples[#:eval ev #:label #f
(column-names (read-ndjson "stations.ndjson" #:infer-schema-length 2))
(eval:error (read-ndjson "stations.ndjson" #:infer-schema-length 1))
(~> (read-ndjson "stations.ndjson" #:infer-schema-length 1 #:ignore-errors #t)
    (select "station" "reading"))
]

@bold{Rows and files.} @racket[#:n-rows] caps the rows read,
@racket[#:row-index-name] adds a column of row numbers and
@racket[#:include-file-paths] one naming each row's file. The path is a
glob pattern, as for Parquet:

@examples[#:eval ev #:label #f
(for ([i '(1 2 3)])
  (write-ndjson (read-csv (format "parts/part-~a.csv" i))
                (build-path dir (format "part-~a.ndjson" i))))
(read-ndjson (build-path dir "part-*.ndjson") #:n-rows 4 #:row-index-name "row")
]

API gaps: a path only, no file object or in-memory string in or out; an
Enum in @racket[#:schema], read as @racket['categorical] and
@racket[cast] instead. Compressed input is recognised by its first bytes,
not its name, as in Python, so a plain file that happens to start like a
gzip, zlib or zstd stream fails with a decompression error.

@examples[#:eval ev #:hidden
(delete-directory/files dir)
]

@(close-eval ev)
