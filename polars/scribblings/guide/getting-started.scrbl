#lang scribble/manual
@require[@for-label[polars
                    (only-in threading ~> ~>>)
                    (except-in racket/base min max sort filter reverse and or not when + - * / > < >= <= = abs round floor sqrt exp log)]]

@title[#:tag "getting-started"]{Getting started}

Mirrors the upstream
@hyperlink["https://docs.pola.rs/user-guide/getting-started/"]{Getting
started} page. Scripts: @tt{user-guide/getting-started/}.

@section{Installing}

@verbatim|{
  raco pkg install polars
}|

@racketblock[(require polars)]

@section[#:tag "gs-reading-writing"]{Reading & writing}

A @tech{dataframe} is built from named @tech{series}. gregor datetimes become
datetime columns; cast to get a date column.

@racketblock[
(require gregor polars)

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
]

@verbatim|{
shape: (4, 4)
┌────────────────┬────────────┬────────┬────────┐
│ name           ┆ birthdate  ┆ weight ┆ height │
│ ---            ┆ ---        ┆ ---    ┆ ---    │
│ str            ┆ date       ┆ f64    ┆ f64    │
╞════════════════╪════════════╪════════╪════════╡
│ Alice Archer   ┆ 1997-01-10 ┆ 57.9   ┆ 1.56   │
│ Ben Brown      ┆ 1985-02-15 ┆ 72.5   ┆ 1.77   │
│ Chloe Cooper   ┆ 1983-03-22 ┆ 53.6   ┆ 1.65   │
│ Daniel Donovan ┆ 1981-04-30 ┆ 83.1   ┆ 1.75   │
└────────────────┴────────────┴────────┴────────┘
}|

Round-trip through CSV with @racket[write-csv] and @racket[read-csv]. Dates
come back as strings; parse them with @racket[str-to-date].

@racketblock[
(write-csv df "output.csv")
(~> (read-csv "output.csv")
    (with-columns (str-to-date "birthdate")))
]

API gaps: no date dtype from gregor @tt{date} values; no
@tt{try_parse_dates} on @racket[read-csv].

@section[#:tag "gs-expressions-contexts"]{Expressions and contexts}

Expressions such as @racket[(col "weight")] describe a computation; a context
(@racket[select], @racket[with-columns], @racket[filter],
@racket[group-by]/@racket[agg]) runs it against a frame.

@subsection[#:tag "gs-select"]{select}

@racketblock[
(~> df
    (select "name"
            (alias (dt-year "birthdate") "birth_year")
            (alias (/ (col "weight") (pow (col "height") 2)) "bmi")))
]

@verbatim|{
shape: (4, 3)
┌────────────────┬────────────┬───────────┐
│ name           ┆ birth_year ┆ bmi       │
│ ---            ┆ ---        ┆ ---       │
│ str            ┆ i32        ┆ f64       │
╞════════════════╪════════════╪═══════════╡
│ Alice Archer   ┆ 1997       ┆ 23.791913 │
│ Ben Brown      ┆ 1985       ┆ 23.141498 │
│ Chloe Cooper   ┆ 1983       ┆ 19.687787 │
│ Daniel Donovan ┆ 1981       ┆ 27.134694 │
└────────────────┴────────────┴───────────┘
}|

@racketblock[
(~> df
    (select "name"
            (alias (round (* (col "weight") 0.95) #:decimals 2) "weight-5%")
            (alias (round (* (col "height") 0.95) #:decimals 2) "height-5%")))
]

API gaps: no multi-column @tt{col("weight", "height")}; no @tt{name.suffix}.

@subsection[#:tag "gs-with-columns"]{with-columns}

@racketblock[
(~> df
    (with-columns (alias (dt-year "birthdate") "birth_year")
                  (alias (/ (col "weight") (pow (col "height") 2)) "bmi")))
]

@subsection[#:tag "gs-filter"]{filter}

@racketblock[
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

@racketblock[
(define decade (alias (* (/ (dt-year "birthdate") 10) 10) "decade"))

(~> df (group-by decade) (agg (alias (count "name") "len")))

(~> df
    (group-by decade)
    (agg (alias (count "name") "sample_size")
         (alias (round (mean "weight") #:decimals 2) "avg_weight")
         (alias (max "height") "tallest")))
]

@verbatim|{
shape: (2, 4)
┌────────┬─────────────┬────────────┬─────────┐
│ decade ┆ sample_size ┆ avg_weight ┆ tallest │
│ ---    ┆ ---         ┆ ---        ┆ ---     │
│ i32    ┆ u32         ┆ f64        ┆ f64     │
╞════════╪═════════════╪════════════╪═════════╡
│ 1990   ┆ 1           ┆ 57.9       ┆ 1.56    │
│ 1980   ┆ 3           ┆ 69.73      ┆ 1.77    │
└────────┴─────────────┴────────────┴─────────┘
}|

API gaps: no @tt{maintain_order}; no @tt{pl.len()} (count a column instead).

@subsection[#:tag "gs-complex"]{More complex queries}

@racketblock[
(~> df
    (with-columns decade
                  (str-extract "name" "^(\\S+)"))
    (drop "birthdate")
    (group-by "decade")
    (agg (col "name")
         (alias (round (mean "weight") #:decimals 2) "avg_weight")
         (alias (round (mean "height") #:decimals 2) "avg_height")))
]

@verbatim|{
shape: (2, 4)
┌────────┬────────────────────────────┬────────────┬────────────┐
│ decade ┆ name                       ┆ avg_weight ┆ avg_height │
│ ---    ┆ ---                        ┆ ---        ┆ ---        │
│ i32    ┆ list[str]                  ┆ f64        ┆ f64        │
╞════════╪════════════════════════════╪════════════╪════════════╡
│ 1990   ┆ ["Alice"]                  ┆ 57.9       ┆ 1.56       │
│ 1980   ┆ ["Ben", "Chloe", "Daniel"] ┆ 69.73      ┆ 1.72       │
└────────┴────────────────────────────┴────────────┴────────────┘
}|

API gaps: no @tt{str.split} / @tt{list.first} (regex @racket[str-extract]
instead); no @tt{all().exclude} (@racket[drop] instead); no
@tt{name.prefix}.

@section[#:tag "gs-combining"]{Combining dataframes}

@subsection[#:tag "gs-joining"]{Joining}

@racketblock[
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

@racketblock[
(vstack df df3)
]

API gap: no n-ary @tt{concat} with a @tt{how}; @racket[vstack] is pairwise
vertical concatenation.
