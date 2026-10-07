#lang scribble/manual
@(require "../utils.rkt"
          racket/runtime-path)

@(define-runtime-path data-dir "../data")
@(define ev (make-polars-eval #:directory data-dir))

@title[#:tag "io-json"]{JSON files}

@see-reference["ref-fluent"]{@racket[read-json] and @racket[write-json]}

Polars can read and write standard JSON, a file that holds one array of
objects.

@examples[#:eval ev #:hidden
(require racket/file)
(define dir (make-temporary-directory "polars-guide-~a"))
(define path (build-path dir "path.json"))
]

@section[#:tag "io-json-read"]{Read}

@subsection[#:tag "io-json-read-json"]{JSON}

Reading a JSON file should look familiar:

@examples[#:eval ev #:label #f
(read-json "stations.json")
]

@section[#:tag "io-json-write"]{Write}

@examples[#:eval ev #:label #f
(define df
  (dataframe (list (series '(1 2 3) #:name "foo")
                   (series (list polars-null "bak" "baz") #:name "bar"))))
(write-json df path)
(file->string path)
(read-json path)
]

Racket's @racketmodname[json] library also provides @racket[read-json] and
@racket[write-json], so @racket[(require polars json)] fails with
``identifier already required''. Rename @racketmodname[json]'s pair with
@racket[(require polars (prefix-in js: json))], or leave it out with
@racket[(require polars (except-in json read-json write-json))].

@section[#:tag "io-json-options"]{Reading options}

Upstream documents @tt{read_json}'s options on its reference page; here they
are with their Racket spellings. @filepath{stations.json} has a
@litchar{reading} that starts as an integer and a @litchar{note} key that
only its last object carries.

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

API gaps: a path only, no file object or in-memory string in or out; an
Enum in @racket[#:schema], read as @racket['categorical] and
@racket[cast] instead.

@examples[#:eval ev #:hidden
(delete-directory/files dir)
]

@(close-eval ev)
