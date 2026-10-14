#lang scribble/manual
@(require "../utils.rkt")

@(define ev (make-polars-eval))

@title[#:tag "expressions" #:style 'toc]{Expressions}

@see-reference["ref-fluent"]{@racket[col], @racket[all], @racket[exclude] and @racket[over]}

@local-table-of-contents[]

@section[#:tag "expressions-expansion"]{Expression expansion}

One expression can stand for several columns; it expands to one expression
per matched column when a context runs it. The stock prices below are
upstream's.

@examples[#:eval ev #:label #f
(define df
  (dataframe
   (list (series '("AAPL" "NVDA" "MSFT" "GOOG" "AMZN") #:name "ticker")
         (series '("Apple" "NVIDIA" "Microsoft" "Alphabet (Google)" "Amazon")
                 #:name "company_name")
         (series '(229.9 138.93 420.56 166.41 188.4) #:name "price")
         (series '(231.31 139.6 424.04 167.62 189.83) #:name "day_high")
         (series '(228.6 136.3 417.52 164.78 188.44) #:name "day_low")
         (series '(237.23 140.76 468.35 193.31 201.2) #:name "year_high")
         (series '(164.08 39.23 324.39 121.46 118.35) #:name "year_low"))))
df
]

@subsection[#:tag "expressions-col"]{Function col}

@subsubsection[#:tag "expressions-col-names"]{Explicit expansion by column name}

API gap: @racket[col] takes one name, so there is no
@tt{pl.col("price", "day_high", ...)}. A list of expressions is spliced into
the context, so build one per name.

@examples[#:eval ev #:label #f
(define eur-usd-rate 1.09)
(~> df
    (with-columns
     (for/list ([name '("price" "day_high" "day_low" "year_high" "year_low")])
       (~> (col name) (/ eur-usd-rate) (round #:decimals 2)))))
]

@subsubsection[#:tag "expressions-col-dtype"]{Expansion by data type}

A dtype selects every column of that dtype; @racket['f64] and
@racket['float64] are the same selector.

@examples[#:eval ev #:label #f
(~> df (with-columns (~> (col 'float64) (/ eur-usd-rate) (round #:decimals 2))))
]

API gap: @racket[col] takes one dtype, and selectors do not compose yet
(#50), so @tt{pl.col(pl.Float32, pl.Float64)} is one expression per dtype.
A dtype no column has matches nothing.

@examples[#:eval ev #:label #f
(~> df
    (with-columns
     (for/list ([type '(float32 float64)])
       (~> (col type) (/ eur-usd-rate) (round #:decimals 2)))))
]

@subsubsection[#:tag "expressions-col-pattern"]{Expansion by pattern matching}

A string of the form @tt{^...$} is a Polars regex, as in Python. The
context takes several specs, where Python's @tt{col} takes several names.

@examples[#:eval ev #:label #f
(select df "ticker" (col "^.*_high$") (col "^.*_low$"))
]

A Racket regexp is also accepted, and keeps its Racket meaning: it selects
exactly the names @racket[regexp-match?] accepts, so it is unanchored unless
it says otherwise.

@examples[#:eval ev #:label #f
(select df "ticker" (col #rx"_(high|low)$"))
(select df (col #px"^\\w+_high$"))
]

Polars' engine has no lookaround or backreferences, so @racket[col] rejects
such a regexp. Match the names in Racket instead.

@examples[#:eval ev #:label #f
(define not-day #px"^(?!day_).*_(high|low)$")
(eval:error (select df (col not-day)))
(select df (filter (lambda (name) (regexp-match? not-day name))
                   (column-names df)))
]

@subsubsection[#:tag "expressions-col-mixed"]{Arguments cannot be of mixed types}

Each @racket[col] is one name, dtype or pattern, so the mixture is written
as separate specs.

@examples[#:eval ev #:label #f
(select df "ticker" (col 'float64))
]

@subsection[#:tag "expressions-all"]{Selecting all columns}

@examples[#:eval ev #:label #f
(select df (all))
]

API gap: no @tt{DataFrame.equals}.

@subsection[#:tag "expressions-exclude"]{Excluding columns}

@racket[exclude] takes names, Polars regex strings and Racket regexps, read
as @racket[col] reads them, and applies to any multi-column expression.

@examples[#:eval ev #:label #f
(select df (exclude (all) "^day_.*$"))
(select df (~> (col 'float64) (exclude #rx"^day_")))
]

API gap: no @tt{exclude} by dtype.

@subsection[#:tag "expressions-renaming"]{Column renaming}

An expanded expression keeps each matched column's name, so two
expressions over the same column collide.

@examples[#:eval ev #:label #f
(define gbp-usd-rate 1.31)
(eval:error (select df
                    (/ (col "price") gbp-usd-rate)
                    (/ (col "price") eur-usd-rate)))
]

@subsubsection[#:tag "expressions-alias"]{Renaming a single column with alias}

@examples[#:eval ev #:label #f
(select df
        (~> (col "price") (/ gbp-usd-rate) (alias "price (GBP)"))
        (~> (col "price") (/ eur-usd-rate) (alias "price (EUR)")))
]

@subsubsection[#:tag "expressions-prefix-suffix"]{Prefixing and suffixing column names}

API gap: no @tt{name.prefix} / @tt{name.suffix} (#51). Alias each column,
taking the names from the frame.

@examples[#:eval ev #:label #f
(select df
        (for/list ([name (column-names df)]
                   #:when (regexp-match? #rx"^year_" name))
          (~> (col name) (/ eur-usd-rate) (alias (string-append "in_eur_" name))))
        (for/list ([name '("day_high" "day_low")])
          (~> (col name) (/ gbp-usd-rate) (alias (string-append name "_gbp")))))
]

@subsubsection[#:tag "expressions-name-map"]{Dynamic name replacement}

API gap: no @tt{name.map}; the same loop applies any Racket function to the
names.

@examples[#:eval ev #:label #f
(select df (for/list ([name (column-names df)])
             (alias (col name) (string-upcase name))))
]

@subsection[#:tag "expressions-generating"]{Programmatically generating expressions}

Build the expressions first, then hand them to one context.

@examples[#:eval ev #:label #f
(define (amplitude-expressions time-periods)
  (for/list ([tp (in-list time-periods)])
    (~> (col (string-append tp "_high"))
        (- (col (string-append tp "_low")))
        (alias (string-append tp "_amplitude")))))
(~> df (with-columns (amplitude-expressions '("day" "year"))))
]

@subsection[#:tag "expressions-selectors"]{More flexible column selections}

API gap: no @tt{polars.selectors}, and selectors do not compose with set
operations yet (#50). A union of disjoint selections is a list of specs;
anything else is a Racket filter over the names.

@examples[#:eval ev #:label #f
(select df (col 'string) (col #rx"_high$"))
(select df (filter (lambda (name)
                     (and (regexp-match? #rx"_" name)
                          (~> (ref df name) dtype (eq? 'string) not)))
                   (column-names df)))
]

@subsubsection[#:tag "expressions-debugging-selectors"]{Debugging selectors}

@racket[multi-column-expr?] plays @tt{cs.is_selector}, an expression prints
as its plan, and selecting from the frame lists what a selector matches.

@examples[#:eval ev #:label #f
(define people
  (dataframe (list (series '("Anna" "Bob") #:name "name")
                   (series '(#t #f) #:name "has_partner")
                   (series '(#f #f) #:name "has_kids")
                   (series '(#t #f) #:name "has_tattoos")
                   (series '(#t #t) #:name "is_alive"))))
(select people (not (col #rx"^has_")))
(~> (col #rx"^has_") not multi-column-expr?)
(not (col #rx"^has_"))
(~> people (select (col #rx"^has_")) column-names)
]

@racket[meta-root-names] and @racket[meta-output-name] read the plan
without a frame: a named expression reports its inputs and output, and a
selector, by regexp or by dtype, nothing.

@examples[#:eval ev #:label #f
(for/list ([e (amplitude-expressions '("day" "year"))])
  (list (meta-output-name e) (meta-root-names e)))
(meta-root-names (col #rx"^has_"))
(eval:error (meta-output-name (col #rx"^has_")))
(meta-root-names (col 'bool))
(eval:error (meta-output-name (col 'bool)))
]

@section[#:tag "expressions-categoricals"]{Categorical data and enums}

A column of strings drawn from a small set can be stored as a dictionary:
each distinct string once, a code per row. An Enum declares its categories,
in order, up front; a categorical infers them as data arrives. Prefer an
Enum when the categories are known. Both read back as symbols. See
@secref["ref-categorical"].

@subsection[#:tag "categoricals-enum"]{Data type Enum}

@subsubsection[#:tag "categoricals-enum-creating"]{Creating an Enum}

@examples[#:eval ev #:label #f
(define-enum bears-enum Polar Panda Brown)
(define bears (series '(Polar Panda Brown Brown Polar) #:dtype bears-enum))
bears
]

@subsubsection[#:tag "categoricals-enum-invalid"]{Invalid values}

@examples[#:eval ev #:label #f
(eval:error (series '(Polar Panda Brown Polar Shark) #:dtype bears-enum))
]

@subsubsection[#:tag "categoricals-enum-order"]{Category ordering and comparison}

An Enum sorts and compares in the order of its categories.

@examples[#:eval ev #:label #f
(define-enum log-levels debug info warning error)
(define logs
  (dataframe
   (list (series '(debug info debug error) #:name "level" #:dtype log-levels)
         (series '("process id: 525" "Service started correctly"
                   "startup time: 67ms" "Cannot connect to DB!")
                 #:name "message"))))
(define non-debug-logs (filter logs (> (col "level") 'debug)))
non-debug-logs
]

A value outside the categories is an error:

@examples[#:eval ev #:label #f
(eval:error (select logs (> (col "level") "Pretty bad")))
]

An Enum compares with an Enum, or with strings that are its categories:

@examples[#:eval ev #:label #f
(define str-series (series '("info" "debug" "debug" "error")))
(= (ref logs "level") str-series)
]

@subsection[#:tag "categoricals-categorical"]{Data type Categorical}

@subsubsection[#:tag "categoricals-categorical-creating"]{Creating a Categorical series}

@examples[#:eval ev #:label #f
(define bears-cat (series '(Polar Panda Brown Brown Polar) #:dtype 'categorical))
bears-cat
(dtype (series '(Polar Panda)))
]

@subsubsection[#:tag "categoricals-categories"]{Using Categories objects}

API gap: no @tt{pl.Categories}. Every categorical column shares Polars' one
global mapping.

@subsubsection[#:tag "categoricals-lexical"]{Lexical comparison with strings}

A categorical compares with strings by the strings, not by the codes:

@examples[#:eval ev #:label #f
(~> (dataframe (list (rename bears-cat "categorical")))
    (with-columns (alias (< (col "categorical") "Cat") "categorical < \"Cat\"")))
(~> (dataframe (list (rename bears-cat "categorical")
                     (series '("Panda" "Brown" "Brown" "Polar" "Polar") #:name "string")))
    (with-columns (alias (= (col "categorical") (col "string")) "categorical == string")))
]

@subsubsection[#:tag "categoricals-combining"]{Combining categorical columns}

Categorical columns share the global mapping, so they stack with no
re-encoding:

@examples[#:eval ev #:label #f
(define male-bears
  (dataframe (list (series '(Polar Brown Panda) #:name "species")
                   (series '(450 500 110) #:name "weight"))))
(define female-bears
  (dataframe (list (series '(Brown Polar Panda) #:name "species")
                   (series '(340 200 90) #:name "weight"))))
(vstack male-bears female-bears)
]

@subsection[#:tag "categoricals-performance"]{Performance considerations}

@subsubsection[#:tag "categoricals-encodings"]{Encodings}

The codes are small integers, so grouping, joining and comparing work on
integers, not strings. They stay inside Polars: Racket sees symbols, which
Racket interns, so a conversion builds one symbol per distinct string.

@subsubsection[#:tag "categoricals-enum-encodings"]{Enum encodings are fixed}

An Enum's codes follow its declared categories, so two columns of one Enum
share an encoding and need no re-encoding.

@subsubsection[#:tag "categoricals-categorical-encodings"]{Categorical encodings}

A categorical's codes come from the global mapping in order of first
appearance, across every categorical column in the process; the mapping
restarts once the last categorical column is gone. API gap: no
@tt{Series.extend}, so stack one-column frames:

@examples[#:eval ev #:label #f
(define cat-bears (series '(Polar Panda Brown Brown Polar) #:dtype 'categorical))
(define cat2-series (series '(Panda Brown Brown Polar Polar) #:dtype 'categorical))
(ref (vstack (dataframe (list cat-bears)) (dataframe (list cat2-series))) 0)
]

@section[#:tag "expressions-window"]{Window functions}

A window function computes an expression within groups and maps the result
back onto the rows, so the frame keeps its height. The Pokémon below are the
first rows of upstream's table.

@examples[#:eval ev #:label #f
(define-enum types
  Grass Water Fire Normal Ground Electric Psychic Fighting Bug Steel
  Flying Dragon Dark Ghost Poison Rock Ice Fairy)
(define pokemon
  (dataframe
   (list (series '("Bulbasaur" "Ivysaur" "Venusaur" "Charmander" "Charmeleon"
                   "Charizard" "Mega Charizard X" "Squirtle"
                   "Wartortle" "Blastoise")
                 #:name "Name")
         (series '(Grass Grass Grass Fire Fire Fire Fire Water Water Water)
                 #:name "Type 1" #:dtype types)
         (series (list 'Poison 'Poison 'Poison polars-null polars-null
                       'Flying 'Dragon polars-null polars-null polars-null)
                 #:name "Type 2" #:dtype types)
         (series '(49 62 82 52 64 84 130 48 63 83) #:name "Attack")
         (series '(45 60 80 65 80 100 100 43 58 78) #:name "Speed"))))
pokemon
]

@subsection[#:tag "window-per-group"]{Operations per group}

@examples[#:eval ev #:label #f
(select pokemon
        "Name" "Type 1"
        (~> (col "Speed")
            (rank #:method 'dense #:descending #t)
            (over "Type 1")
            (alias "Speed rank")))
(select pokemon
        "Name" "Type 1" "Type 2"
        (~> (col "Speed")
            (rank #:method 'dense #:descending #t)
            (over "Type 1" "Type 2")
            (alias "Speed rank")))
]

@subsection[#:tag "window-mapping"]{Mapping results to dataframe rows}

API gap: @racket[over] has no @tt{mapping_strategy}; it always maps as
@tt{group_to_rows}.

@examples[#:eval ev #:label #f
(define athletes
  (dataframe (list (series '("A" "B" "C" "D" "E" "F") #:name "athlete")
                   (series '("PT" "NL" "NL" "PT" "PT" "NL") #:name "country")
                   (series '(6 1 5 4 2 3) #:name "rank"))))
athletes
]

@subsubsection[#:tag "window-group-to-rows"]{group_to_rows}

Each group's result goes back to the rows the group came from. A regexp
@racket[col] stands in for @tt{pl.col("athlete", "rank")}.

@examples[#:eval ev #:label #f
(select athletes
        (~> (col #rx"^(athlete|rank)$")
            (sort-by #:by (col "rank"))
            (over (col "country")))
        (col "country"))
]

@subsubsection[#:tag "window-explode"]{explode}

API gap: no @tt{explode} strategy. Sorting the frame by the key and then the
value gives the same rows, with the groups in key order rather than in order
of first appearance.

@examples[#:eval ev #:label #f
(sort athletes '("country" "rank"))
]

@subsubsection[#:tag "window-join"]{join}

API gap: no @tt{join} strategy. Collect each group's values with
@racket[agg] and join them back.

@examples[#:eval ev #:label #f
(join (drop athletes "rank")
      (~> athletes (group-by "country") (agg (sort-by (col "rank") #:by "rank")))
      #:on '("country")
      #:how 'left)
]

@subsection[#:tag "window-aggregation"]{Windowed aggregation expressions}

An aggregation over a window is repeated on every row of its group.

@examples[#:eval ev #:label #f
(select pokemon
        "Name" "Type 1" "Speed"
        (~> (col "Speed") mean (over (col "Type 1")) (alias "Mean speed in group")))
]

@subsection[#:tag "window-more"]{More examples}

API gap: without @tt{explode}, the three fastest of each type are picked as
rows instead: rank within the window, then filter. The strongest and the
alphabetical first three follow the same pattern over @racket["Attack"]
and @racket["Name"].

@examples[#:eval ev #:label #f
(~> pokemon
    (with-columns (~> (col "Speed")
                      (rank #:method 'ordinal #:descending #t)
                      (over "Type 1")
                      (alias "fastest/group")))
    (filter (<= (col "fastest/group") 3))
    (select "Type 1" "Name" "fastest/group")
    (sort '("Type 1" "fastest/group")))
]

@(close-eval ev)
