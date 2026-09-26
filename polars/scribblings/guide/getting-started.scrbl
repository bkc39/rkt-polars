#lang scribble/manual
@(require "../utils.rkt")

@(define ev (make-polars-eval))

@title[#:tag "getting-started" #:style 'toc]{Getting started}

@see-reference["ref-fluent"]{the definition of every verb used here}

@local-table-of-contents[]

@section[#:tag "gs-installing"]{Installing}

@commandline{raco pkg install polars}

@racketblock[(require gregor polars)]

@section[#:tag "gs-reading-writing"]{Reading & writing}

A @tech{dataframe} is built from named @tech{series}. gregor datetimes become
datetime columns; cast to get a date column.

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

Round-trip through CSV with @racket[write-csv] and @racket[read-csv]. Dates
come back as strings; parse them with @racket[str-to-date].

@examples[#:eval ev #:hidden
(define csv-path (build-path (find-system-path 'temp-dir) "polars-guide.csv"))
]

@examples[#:eval ev #:label #f
(write-csv df csv-path)
(~> (read-csv csv-path)
    (with-columns (str-to-date "birthdate")))
]

@examples[#:eval ev #:hidden
(delete-file csv-path)
]

API gaps: no date dtype from gregor @tt{date} values; no
@tt{try_parse_dates} on @racket[read-csv].

@section[#:tag "gs-expressions-contexts"]{Expressions and contexts}

Expressions such as @racket[(col "weight")] describe a computation; a context
(@racket[select], @racket[with-columns], @racket[filter],
@racket[group-by]/@racket[agg]) runs it against a frame.

@subsection[#:tag "gs-select"]{select}

@examples[#:eval ev #:label #f
(~> df
    (select "name"
            (~> (col "birthdate") dt-year (alias "birth_year"))
            (~> (col "weight") (/ (pow (col "height") 2)) (alias "bmi"))))
(~> df
    (select "name"
            (~> (col "weight") (* 0.95) (round #:decimals 2) (alias "weight-5%"))
            (~> (col "height") (* 0.95) (round #:decimals 2) (alias "height-5%"))))
]

API gaps: no multi-column @tt{col("weight", "height")}; no @tt{name.suffix}.

@subsection[#:tag "gs-with-columns"]{with-columns}

@examples[#:eval ev #:label #f
(~> df
    (with-columns (~> (col "birthdate") dt-year (alias "birth_year"))
                  (~> (col "weight") (/ (pow (col "height") 2)) (alias "bmi"))))
]

@subsection[#:tag "gs-filter"]{filter}

@examples[#:eval ev #:label #f
(~> df (filter (< (dt-year "birthdate") 1990)))
(~> df
    (filter (and (is-between "birthdate"
                             (cast (lit "1982-12-31") 'date)
                             (cast (lit "1996-01-01") 'date))
                 (> (col "height") 1.7))))
]

API gaps: no date literals; @racket[filter] takes one predicate, so combine
with @racket[and].

@subsection[#:tag "gs-group-by"]{group-by}

@racket[/] on an integer column is integer division, so Python's
@tt{// 10 * 10} is @racket[(* (/ _e 10) 10)].

@examples[#:eval ev #:label #f
(define decade
  (~> (col "birthdate") dt-year (/ 10) (* 10) (alias "decade")))
(~> df (group-by decade) (agg (~> (col "name") count (alias "len"))))
(~> df
    (group-by decade)
    (agg (~> (col "name") count (alias "sample_size"))
         (~> (col "weight") mean (round #:decimals 2) (alias "avg_weight"))
         (~> (col "height") max (alias "tallest"))))
]

API gaps: no @tt{maintain_order}, so row order differs from the Python pair;
no @tt{pl.len()} (count a column instead).

@subsection[#:tag "gs-complex"]{More complex queries}

@examples[#:eval ev #:label #f
(~> df
    (with-columns decade
                  (str-extract "name" "^(\\S+)"))
    (select (exclude (all) "birthdate"))
    (group-by "decade")
    (agg (col "name")
         (~> (col "weight") mean (round #:decimals 2) (alias "avg_weight"))
         (~> (col "height") mean (round #:decimals 2) (alias "avg_height"))))
]

API gaps: no @tt{str.split} / @tt{list.first} (regex @racket[str-extract]
instead); no @tt{name.prefix}.

@section[#:tag "gs-combining"]{Combining dataframes}

@subsection[#:tag "gs-joining"]{Joining}

@examples[#:eval ev #:label #f
(define df2
  (dataframe
   (list (series '("Ben Brown" "Daniel Donovan" "Alice Archer" "Chloe Cooper")
                 #:name "name")
         (series '(#t #f #f #f) #:name "parent")
         (series '(1 2 3 4) #:name "siblings"))))
(join df df2 #:on '("name") #:how 'left)
]

API gap: @racket[#:on] takes a list of names, not a bare name.

@subsection[#:tag "gs-concatenating"]{Concatenating}

@examples[#:eval ev #:label #f
(define df3
  (~> (dataframe
       (list (series '("Ethan Edwards" "Fiona Foster" "Grace Gibson" "Henry Harris")
                     #:name "name")
             (series (list (datetime 1977 5 10) (datetime 1975 6 23)
                           (datetime 1973 7 22) (datetime 1971 8 3))
                     #:name "birthdate")
             (series '(67.9 72.5 57.6 93.1) #:name "weight")
             (series '(1.76 1.6 1.66 1.8) #:name "height")))
      (with-columns (cast "birthdate" 'date))))
(vstack df df3)
]

API gap: no n-ary @tt{concat} with a @tt{how}; @racket[vstack] is pairwise
vertical concatenation.

@(close-eval ev)
