#lang scribble/manual
@(require "utils.rkt"
          racket/runtime-path
          syntax/parse/define
          (for-syntax racket/base syntax/strip-context))

@(define-runtime-path data-dir "data")
@(define ev (make-polars-eval #:directory data-dir))

@(require (only-in polars/private/csv
                   csv-read-arguments csv-scan-arguments csv-write-arguments)
          (only-in polars/private/json ndjson-arguments ndjson-writer-arguments)
          (only-in polars/private/parquet
                   parquet-read-arguments parquet-scan-arguments parquet-write-arguments))

@(define-syntax json-arguments
   (quote-syntax
    ([#:schema schema (or/c json-schema/c #f) #f]
     [#:schema-overrides schema-overrides json-schema/c '()]
     [#:infer-schema-length infer-schema-length (or/c positive-size/c #f) 100])))

@(define-syntax-parser defproc/arguments
   [(_ arguments:id (name leading ... result) body ...)
    #:with (argument ...) (replace-context #'name (syntax-local-value #'arguments))
    #'(defproc (name leading ... argument ...) result body ...)])

@title[#:tag "reference"]{Reference}

@racketmodname[polars] is written to read as ordinary Racket. The operators
you already know --- @racket[+], @racket[*], @racket[>], @racket[and],
@racket[filter], @racket[sort], @racket[first] --- are overloaded to work on
@tech{series} and @tech{expression}s, dispatching at runtime on what they are
given and falling back to their @racketmodname[racket/base] behaviour on
plain values. @secref["ref-fluent"] documents that surface and comes first
because it is the one to learn.

Underneath sits a monomorphic, dtype-suffixed layer (@racket[series-new-i32],
@racket[series-sum-f64], @racket[expr-add] and friends). It is documented here
for completeness --- see @secref["ref-expressions"] and the low-level
subsections --- but the generic spelling is the preferred one throughout.

A count, position or option that Polars holds in a fixed-width integer is
contracted by its @deftech{integer range}, which the signatures name:
@racket[uint8/c], @racket[uint16/c], @racket[uint32/c] and @racket[uint64/c]
are the unsigned 8-, 16-, 32- and 64-bit integers, @racket[int32/c] and
@racket[int64/c] the signed 32- and 64-bit ones, @racket[nonnegative-int64/c]
an @racket[int64/c] from @racket[0], @racket[size/c] a native size (an
unsigned 64-bit integer) and @racket[positive-size/c] one from @racket[1].
@racket[row-index/c] is a @racket[uint32/c] and @racket[column-index/c] an
@racket[int64/c]. A value outside its range is a contract error that names
the range.

@section[#:tag "ref-fluent"]{Operators and pipelines}

This is the surface to write @racketmodname[polars] in. An
@deftech{expression} describes a column computation without running it, and
the operators below are the ordinary Racket ones --- @racket[+], @racket[*],
@racket[>], @racket[and], @racket[filter], @racket[sort] --- overloaded to
build expressions when an operand is one, while behaving exactly as
@racketmodname[racket/base] does on plain numbers and lists. Nothing about a
pipeline needs a Polars-specific spelling.

Every operation takes the frame --- or the expression --- as its first
argument, so it chains with thread-first @racket[~>] (re-provided from
@racketmodname[threading], so @racket[(require polars)] is enough):

@racketblock[
(~> df
    (filter (> (col "value") 15))
    (group-by "group")
    (agg (alias (sum (col "value")) "sum_value")))
]

A @racket[utf-8-name/c] in a signature below is a column name: a string, or a
byte string or path whose bytes are UTF-8. Any other byte string or path is a
contract error. A @racket[utf-8-names/c] is a list of them.

@defproc[(Expr-ptr? [v any/c]) boolean?]{
  Returns @racket[#t] if @racket[v] is an @tech{expression}.}

@deftogether[(@defproc[(col [spec (or/c string? regexp? dtype-spec?)]) Expr-ptr?]
              @defproc[(lit [v (or/c boolean?
                                     (integer-in (- (expt 2 63)) (sub1 (expt 2 64)))
                                     (and/c real? (not/c exact-integer?)) string? symbol?
                                     polars-null? #,(tt "gregor-value"))])
                       Expr-ptr?]
              @defproc[(dtype-spec? [v any/c]) boolean?])]{
  The leaves every other operation builds on. @racket[col] refers to one
  column or to several at once, by the shape of @racket[spec]:

  @itemlist[
    @item{A string is the column of that name (@tt{pl.col("name")}). A
      string of the form @tt{^...$} is a Polars regex, in the syntax of
      Rust's regex crate, as in Python.}
    @item{A dtype is every column of that dtype (@tt{pl.col(pl.Float64)}).
      @racket[dtype-spec?] is any spelling @racket[series]'
      @racket[#:dtype] accepts, so @racket['float64] and @racket['f64]
      alike. A bare @racket['datetime] means microseconds: the unit
      @racket[#:try-parse-dates] gives parsed datetimes, and the unit
      @racket[series] gives gregor datetimes unless one carries a
      sub-microsecond part and a nanosecond column holds them all, which
      makes the column nanoseconds (@secref["ref-temporal-values"]). Match
      another unit with its @racket[dtype]. A datetime dtype without a zone
      matches only naive columns, and @racket['(datetime unit "Zone/Name")]
      only the columns of that unit in exactly that zone, as
      @tt{pl.col(pl.Datetime("us", "Europe/Brussels"))} does. API gap: no
      spelling selects every datetime column whatever its unit or zone, as
      @tt{pl.col(pl.Datetime)} and @tt{pl.Datetime("us", "*")} do (#171).
      @racket['categorical] is every categorical column, and an
      @racket['(enum ....)] dtype the columns of exactly that Enum
      (@secref["ref-categorical"]).}
    @item{A regexp is every column whose name matches
      (@tt{pl.col("^sepal_.*$")}), keeping the regexp's Racket meaning:
      @racket[(col rx)] selects exactly the names
      @racket[(regexp-match? rx name)] accepts, in @litchar{#rx} and
      @litchar{#px} syntax alike. There are two exceptions. A
      @litchar{\p{...}} property class follows each side's own version of
      the Unicode tables. And Racket's own matcher misjudges some classes
      containing characters above U+00FF; there the selection follows
      the class as written. The crate has no
      lookaround, backreferences, atomic groups or conditionals, so
      @racket[col] (and @racket[exclude]) rejects a regexp using them with
      a contract violation naming the construct. To select by such a regexp, match
      @racket[column-names] in Racket and select the names, as in the
      last example below.}]

  A multi-column @racket[col] expands inside any expression to one output
  per matched column, in the frame's column order, each keeping the
  matched column's name; a frame with no match yields no columns.

  @racket[lit] lifts a Racket scalar to a literal expression: booleans,
  exact integers (32-bit when they fit, 64-bit otherwise, and from
  @racket[(expt 2 63)] to @racket[(sub1 (expt 2 64))] unsigned 64-bit, as
  @tt{pl.lit(2**63)} is; one outside that range is a contract error),
  other reals (as @racket['float64]) and strings. A symbol is the string of its name, so a
  categorical column compares with the symbols it reads back as. A
  @tt{gregor-value} is a gregor @tt{date}, @tt{time}, @tt{datetime},
  @tt{moment} or @tt{period}, and becomes a literal of the dtype
  @racket[series] infers for it (@secref["ref-temporal-values"]), so a
  temporal column compares with gregor values as Python's compares with
  @tt{date}, @tt{time}, @tt{datetime} and @tt{timedelta}. A moment is a
  zoned literal: in its named zone, or in UTC for a fixed offset. A zoned
  column compares only with a literal in its own zone, as in Python.
  @racket[polars-null] is a null of dtype @racket['null], as
  @tt{pl.lit(None)} is: it broadcasts to a @racket['null] column and
  compares as null, so @racket[(= (col "x") polars-null)] is null on every
  row (test with @racketid[is-null] instead). In arithmetic it takes a
  numeric operand's dtype, and with a temporal operand it raises, as in
  Python. Every operator below lifts a
  non-expression operand with @racket[lit] automatically, so it is rarely
  needed explicitly.

  @examples[#:eval ev
(define people
  (dataframe (list (series '(1 2 3) #:name "id" #:dtype 'i32)
                   (series '(57.9 72.5 53.6) #:name "weight")
                   (series '(1.56 1.77 1.65) #:name "height"))))
(select people (* (col 'float64) 1.1))
(list (dtype-spec? 'f64) (dtype-spec? 'float))
(select people (col "^.*ght$"))
(select people (col #rx"^he"))
(select people (col #px"^\\w+t$"))
(select people (~> (col "id") (* 10) (alias "id10"))
               (alias (lit 0) "zero"))
(lit (date 2013 6 1))
(select people (alias (lit (datetime 2013 6 1 12 30)) "noon"))
(select people (alias (lit (moment 2013 6 1 12 30 #:tz "Europe/Paris")) "noon"))
(select people (alias (lit polars-null) "nothing") (= (col "id") polars-null)
        (+ (col "weight") polars-null))
(eval:error (col #px"^(?!id)"))
(select people (filter (lambda (name) (regexp-match? #px"^(?!id)" name))
                       (column-names people)))
(define counters
  (dataframe (list (series (list (sub1 (expt 2 64)) 1) #:name "u" #:dtype 'u64))))
(select counters (alias (lit (sub1 (expt 2 64))) "top")
        (= (col "u") (lit (sub1 (expt 2 64)))))
(eval:error (lit (expt 2 64)))]}

@deftogether[(@defproc[(all) Expr-ptr?]
              @defproc[(exclude [e multi-column-expr?] [name (or/c string? regexp?)] ...+)
                       Expr-ptr?]
              @defproc[(multi-column-expr? [v any/c]) boolean?])]{
  @racket[(all)] is every column (@tt{pl.all()}); inside @racket[agg] it is
  every column that is not a group key. @racket[exclude] removes columns
  from a multi-column expression --- @racket[(all)], or a dtype or regexp
  @racket[col], or any expression built over one --- by name or by regexp
  (@tt{.exclude}), each read as @racket[col] reads it, so a name of the
  form @tt{^...$} is a Polars regex. A name the frame does not have is
  ignored, and chained @racket[exclude]s accumulate. @racket[multi-column-expr?] recognises the
  expressions @racket[exclude] accepts: those that expand to one output
  per matched column. To drop columns from a frame eagerly, @racket[drop]
  is the direct spelling.

  @examples[#:eval ev
(select people (all))
(select people (exclude (all) "id"))
(select people (exclude (all) #rx"^w" "id"))
(select people (exclude (all) "^h.*$"))
(select people (~> (col 'float64) (exclude "height") (* 2)))
(select people (~> (all) (exclude "id") (exclude "weight")))
(~> people
    (with-columns (~> (col "height") (> 1.6) (alias "tall")))
    (group-by "tall")
    (agg (~> (all) (exclude "id") mean))
    (sort "tall"))
(multi-column-expr? (col "id"))
(~> (col 'float64) (* 2) multi-column-expr?)
(eval:error (exclude (col "id") "weight"))]}

@defproc[(expr->string [e Expr-ptr?]) string?]{
  Renders @racket[e] as its plan, in the notation Polars itself uses:
  @tt{col("v")} for a column, @tt{[(a) + (b)]} for a binary operation,
  @tt{.alias("n")} and @tt{.sum()} as method suffixes. This is also what an
  expression prints as at the REPL and throughout this manual, so an
  expression is a value you can read, not an opaque pointer. A regexp
  @racket[col] prints as the Polars pattern it is translated to. When
  Polars cannot print the plan, as for a literal date outside chrono's
  years, @racket[expr->string] raises with Polars' reason and the
  expression prints as a placeholder.

  @examples[#:eval ev
(col "weight")
(alias (* (col "v") 10) "v10")
(expr->string (> (col "v") 2))
(~> (col "v") sum (over "k"))
(exclude (all) "id")
(col 'float64)
(col #rx"^he")
(define far-date (cast (series '(2000000000) #:dtype 'i32 #:name "d") 'date))
(is-in "d" far-date)
(eval:error (expr->string (is-in "d" far-date)))]}

@defproc[(expr-drop [e Expr-ptr?]) void?]{
  Releases the native expression @racket[e] holds now, as
  @racket[series-drop] releases a series. A dropped expression still
  answers to @racket[Expr-ptr?] and prints as
  @racketresultfont{#<expr: dropped>}, and any later use raises
  @racket[exn:fail:contract]: dropping it again names @racket[expr-drop],
  and any other use names the expression, as
  @racketerror{expr: expression has been dropped}. As for a series, a drop
  must not run while another thread uses the same expression.

  @examples[#:eval ev
(define threshold (> (col "v") 2))
(expr-drop threshold)
threshold
(eval:error (filter (dataframe (list (series '(1 3) #:name "v"))) threshold))
(eval:error (expr-drop threshold))]}

@deftogether[(@defproc[(meta-output-name [e (or/c Expr-ptr? string?)]) string?]
              @defproc[(meta-root-names [e (or/c Expr-ptr? string?)]) (listof string?)]
              @defproc[(meta-eq? [a (or/c Expr-ptr? string?)] [b (or/c Expr-ptr? string?)]) boolean?])]{
  Polars' @tt{.meta} namespace: what an expression will do, read off the plan
  without running it. @racket[meta-output-name] is the column the expression
  produces --- the alias if it has one, else its first column, else
  @racket["literal"]; it raises when that cannot be known without a frame.
  @racket[meta-root-names] lists the columns the expression reads, in tree
  order, duplicates included. @racket[meta-eq?] is structural equality of two
  plans; @racket[equal?] on expressions is identity. A column name is lifted
  with @racket[col] wherever an expression is expected.

  A multi-column expression is read off the plan too, before any frame
  says which columns it will match, so a regexp or dtype @racket[col] or
  @racket[(all)] has no root names and no output name, as in Python.

  @examples[#:eval ev
(define total (alias (sum (+ (col "a") (col "b"))) "total"))
total
(meta-output-name total)
(meta-root-names total)
(meta-eq? total (alias (sum (+ (col "a") (col "b"))) "total"))
(meta-eq? total (col "a"))
(equal? total (~> (+ (col "a") (col "b")) sum (alias "total")))
(meta-output-name (+ (col "a") (col "b")))
(meta-output-name (lit 25))
(meta-root-names "a")
(meta-root-names (col #rx"^he"))
(eval:error (meta-output-name (col #rx"^he")))
(~> (col 'float64) (* 2) meta-root-names)
(meta-eq? (col 'float64) (col 'f64))
(eval:error (meta-output-name (col 'float64)))
(eval:error (meta-output-name "*"))
(eval:error (meta-output-name 5))]}

@deftogether[(@defproc[(> [a any/c] [b any/c] ...) any/c]
              @defproc[(< [a any/c] [b any/c] ...) any/c]
              @defproc[(>= [a any/c] [b any/c] ...) any/c]
              @defproc[(<= [a any/c] [b any/c] ...) any/c]
              @defproc[(= [a any/c] [b any/c] ...) any/c]
              @defproc[(!= [a any/c] [b any/c] ...) any/c])]{
  Overloaded comparison operators. If an operand is an expression, they build a
  comparison @emph{expression} (scalars are lifted automatically), so
  @racket[(> (col "value") 15)] reads like @tt{col("value") > 15}. If an operand
  is a series, they build an eager boolean-mask series — element-wise over every
  numeric dtype, including @racket['int64] — so @racket[(> (ref df #:columns "value") 15)]
  is a mask. Otherwise they fall back to the numeric @racketmodname[racket/base]
  operator and stay variadic, so @racket[(> 3 2)] and @racket[(< 1 2 3)] still
  work. @racket[!=] has no @racketmodname[racket/base] spelling; on numbers it is
  @racket[(not (= _a _b))]. A plain operand beside a series follows
  @secref["promotion"], and dtypes Polars cannot compare raise with its reason
  under the operator's name. These shadow the @racketmodname[racket/base]
  comparisons; see @secref["fluent-shadowing"].

  @examples[#:eval ev #:label #f
(= (series (list polars-null polars-null)) 1)
(> (series '(1 2)) 1.5)
(eval:error (> (series '(1 2)) "a"))]}

@deftogether[(@defform[(and expr ...)]
              @defform[(or expr ...)]
              @defproc[(not [x any/c]) any/c]
              @defproc[(xor [a any/c] [b any/c]) any/c])]{
  Overloaded boolean connectives. When an operand is an expression they build
  the element-wise expression (@racket[expr-and], @racket[expr-or],
  @racket[expr-not], @racket[expr-xor]), so
  @racket[(and (> (col "value") 15) (< (col "cost") 3.0))] is a predicate for
  @racket[filter]. When an operand is a series they compute an eager boolean
  mask, beside another boolean series or a boolean or @racket[polars-null];
  a series of another dtype, @racket['null] included, raises with Polars'
  reason under the connective's name, where Python's @tt{& | ^} are bitwise
  on integers and raise on a Null series.
  Otherwise they behave as the @racketmodname[racket/base] forms:
  @racket[and] and @racket[or] short-circuit and return the deciding value, and
  @racket[not] negates. Note that once @racket[and] or @racket[or] meets an
  expression or series operand it evaluates its remaining operands eagerly to
  combine them. A @racket[polars-null] operand decides nothing: they evaluate
  the operands after it and combine it with an expression or series among
  them, as Python's @tt{pl.lit(None) & e} does. These shadow the
  @racketmodname[racket/base] bindings; see @secref["fluent-shadowing"].

  @examples[#:eval ev #:label #f
(and polars-null (series (list #t #f)))
(or polars-null (series (list #t #f)))
(xor (series '(#t #f)) #t)
(eval:error (not (series '(1 2))))]}

@deftogether[(@defproc[(+ [v any/c] ...) any/c]
              @defproc[(- [v any/c] ...) any/c]
              @defproc[(* [v any/c] ...) any/c]
              @defproc[(/ [v any/c] ...) any/c]
              @defproc[(mod [a any/c] [b any/c] ...+) any/c])]{
  Overloaded arithmetic. When every argument is a number they are the
  @racketmodname[racket/base] operators, and @racket[mod] folds
  @racket[modulo] from the left.
  Otherwise they fold left over the arguments: an expression operand yields an
  expression (via @racket[expr-add], @racket[expr-sub], @racket[expr-mul],
  @racket[expr-div], @racket[expr-mod]), so @racket[(* (col "value") 2)] reads
  like @tt{col("value") * 2}, and a series operand yields an eagerly computed
  series. A plain operand beside a series follows @secref["promotion"], and
  dtypes Polars cannot combine raise with its reason under the operator's
  name. These shadow the @racketmodname[racket/base] bindings; see
  @secref["fluent-shadowing"].

  With one argument, @racket[-] negates (@racket[expr-neg]) and @racket[/] is
  @racket[(/ 1 _v)], each output keeping its own name; @racket[+] and
  @racket[*] return an expression or series operand unchanged, and
  @racket[mod] needs two arguments.

  On integer columns @racket[/] is integer division, rounding toward negative
  infinity, with a null where the divisor is 0: @racket[(/ (col "v") 2)] gives
  -4 for -7, unlike @racket[quotient], and the one-argument reciprocal of an
  integer column is 1, -1, 0 or null. Python's @tt{/} gives floats there;
  @racket[cast] an operand to @racket['f64] first for the same result. A
  signed integer series beside a @racket['uint64] one has no integer
  supertype, so the quotient is @racket['float64], floored, as Python's
  @tt{//} gives it. API gap: the expression form does not floor there yet, so
  @racket[(/ (col "i") (col "u"))] of an Int64 and a UInt64 column, or of an
  integer column and an integer from @racket[(expt 2 63)], is the unfloored
  @racket['float64] quotient (#303).

  @examples[#:eval ev #:label #f
(- 5)
(/ 4)
(mod 10 4 3)
(- (col "delay"))
(/ (col "speed"))
(- (series '(1 -2 3) #:name "v"))
(/ (series '(1.0 2.0 4.0) #:name "v"))
(/ (series '(1 2 4)))
(/ (series '(1 -1 2 -2 0)))
(/ (series '(-7 7 1)) (series '(2 2 0)))
(/ (series '(10 -7) #:name "v") (series '(3 2) #:dtype 'u64))
(/ (cast (series '(1 2 4)) 'f64))
(+ (series (list polars-null polars-null)) 1)
(+ (series '(1 2)) 2.5)
(+ (series '(1 2)) "a")
(eval:error (+ (series '(1 2)) (date 2024 1 1)))
(~> (dataframe (list (series '(1.0 2.0) #:name "c1") (series '(4.0 8.0) #:name "c2")))
    (select (/ (col #rx"^c"))))
(eval:error (- (series '(1 2) #:dtype 'u8)))
(eval:error (/ (series '("a"))))
(eval:error (mod (col "v")))
(~> (dataframe (list (series '(10 25 7) #:name "v")))
    (with-columns (/ (col "v"))))]}

@defproc[(filter [d dataframe?] [predicate any/c]) dataframe?]{
  Keeps the rows of @racket[d] matching @racket[predicate], which may be a
  boolean expression — @racket[(filter df (> (col "value") 15))] — or a
  precomputed boolean-mask series. Returns a new dataframe. Applied to a
  non-dataframe it falls back to @racketmodname[racket/base]'s @racket[filter],
  so @racket[(filter even? '(1 2 3 4))] is @racket['(2 4)].}

@defproc*[([(sort [d dataframe?] [by (or/c string? (non-empty-listof string?))]
                  [#:descending descending (or/c boolean? (listof boolean?)) #f]
                  [#:nulls-last nulls-last (or/c boolean? (listof boolean?)) #f]
                  [#:maintain-order maintain-order boolean? #f])
            dataframe?]
           [(sort [lf lazyframe?] [by (or/c string? (non-empty-listof string?))]
                  [#:descending descending (or/c boolean? (listof boolean?)) #f]
                  [#:nulls-last nulls-last (or/c boolean? (listof boolean?)) #f]
                  [#:maintain-order maintain-order boolean? #f])
            lazyframe?]
           [(sort [s series?]
                  [#:descending descending boolean? #f]
                  [#:nulls-last nulls-last boolean? #f])
            series?]
           [(sort [e (or/c Expr-ptr? string?)]
                  [#:descending descending boolean? #f]
                  [#:nulls-last nulls-last boolean? #f])
            Expr-ptr?]
           [(sort [lst list?] [less-than? (any/c any/c . -> . any/c)]
                  [#:descending descending boolean? #f]
                  [#:key extract-key (or/c #f (any/c . -> . any/c)) #f]
                  [#:cache-keys? cache-keys? boolean? #f])
            list?])]{
  Sorts a @tech{dataframe} or @tech{lazyframe} by the column or columns
  @racket[by] (@tt{df.sort}), or a series by its values (@tt{Series.sort}).
  Given an @tech{expression}, or a column name lifted with @racket[col], it
  builds the expression that sorts that one column (@tt{Expr.sort}). An
  expression whose form makes it one value, or one per group, comes back
  unchanged, because sorting it changes nothing. Such a form is an
  aggregation such as @racket[(sum "v")], a literal, or an operator or
  @racketidfont{when} over those alone.

  Inside @racket[agg] or @racket[over], Polars' own sort reads out of
  bounds when its input holds one value per group, and Python crashes on
  the same query. So @tt{Expr.sort} gets only an input whose form keeps a
  value per row: a column, or an alias, cast, sort, operator or
  @racketidfont{when} with one among its operands. Any other expression, a
  function such as @racket[round] of @racket[(mean "delay")] among them, is
  sorted by itself with @racket[sort-by] (@tt{Expr.sort_by}), which handles
  one value per group. It evaluates the expression twice and prints as a
  @tt{sort_by}.

  Nulls come first, whatever the direction, unless @racket[nulls-last] is
  true; NaN sorts above every other float. For a frame, @racket[descending]
  and @racket[nulls-last] are each one boolean for every key or a list of one
  boolean per key. Rows that tie on every key keep their input order when
  @racket[maintain-order] is true, and are in no particular order otherwise.

  A sorted expression reorders its own column only, so in
  @racket[with-columns] it no longer lines up with the rest of its row. Use it
  in @racket[select] or @racket[agg], and @racket[sort-by] to reorder one
  column by others. A frame sorts by column names only: sorting by an
  expression (@tt{df.sort(pl.col("a") * -1)}) has no spelling yet.

  On a list, @racket[sort] is @racketmodname[racket/base]'s, plus
  @racket[descending], which reverses the order and keeps equal elements in
  their input order, as Python's @tt{sorted(xs, reverse=True)} does. The
  other Polars keywords are a contract violation there.

  @examples[#:eval ev
(define flights
  (dataframe (list (series '("UA" "AA" "UA" "AA" "B6") #:name "carrier")
                   (series (list 12 polars-null 340 -3 polars-null) #:name "delay"))))
(sort flights "delay" #:descending #t)
(~> flights (sort "delay" #:descending #t #:nulls-last #t) (head 2))
(sort flights '("carrier" "delay")
      #:descending '(#f #t) #:nulls-last '(#f #t) #:maintain-order #t)
(~> flights lazy (sort "delay" #:nulls-last #t) collect)
(sort (ref flights #:columns "delay") #:descending #t #:nulls-last #t)
(sort "delay" #:descending #t #:nulls-last #t)
(sort (max "delay") #:descending #t)
(sort (round (mean "delay")) #:descending #t)
(~> flights (group-by "carrier") (agg (sort (round (mean "delay")) #:descending #t)) (sort "carrier"))
(select flights (sort "delay" #:nulls-last #t))
(sort '(3 1 2) <)
(sort '(3 1 2) < #:descending #t)
(sort '((a . 1) (b . 2) (c . 1)) < #:key cdr #:descending #t)
(eval:error (sort '(3 1 2) < #:nulls-last #t))]}

@defproc[(sort-by [x (or/c Expr-ptr? string?)]
                  [#:by by (or/c Expr-ptr? string? (non-empty-listof (or/c Expr-ptr? string?)))]
                  [#:descending descending (or/c boolean? (listof boolean?)) #f]
                  [#:nulls-last nulls-last (or/c boolean? (listof boolean?)) #f]
                  [#:maintain-order maintain-order boolean? #f])
         Expr-ptr?]{
  Builds the expression that reorders the column @racket[x] by the key or keys
  @racket[by] (@tt{Expr.sort_by}); a column name is lifted with @racket[col]
  in either place. The keywords mean what they mean for a frame
  @racket[sort]: one boolean, or one per key. The result keeps @racket[x]'s
  length and name. Inside @racket[agg] or @racket[over] it sorts each group,
  including when @racket[x] is itself group-aware, such as a @racketidfont{shift}.

  @examples[#:eval ev
(define scores
  (dataframe (list (series '("ann" "bob" "cy" "dee") #:name "name")
                   (series (list 3 polars-null 1 3) #:name "score"))))
(select scores (sort-by "name" #:by "score" #:descending #t #:nulls-last #t
                        #:maintain-order #t))
(select scores (sort-by "name" #:by '("score" "name") #:descending '(#t #f)))]}

@deftogether[(@defproc[(select [d (or/c dataframe? lazyframe?)] [spec any/c] ...)
                       (or/c dataframe? lazyframe?)]
              @defproc[(with-columns [d (or/c dataframe? lazyframe?)] [spec any/c] ...)
                       (or/c dataframe? lazyframe?)])]{
  The @emph{select} and @emph{with_columns} contexts. Each @racket[spec] is a
  column name, a column index, an expression, or a list of those (which is
  spliced); names and indices are lifted with @racket[col]. @racket[select]
  returns a frame holding only the resulting columns; @racket[with-columns]
  adds them to (or replaces them in) the existing columns. Given a
  @tech{dataframe} they run eagerly and return a dataframe; given a
  @tech{lazyframe} they extend the plan and return a lazyframe.

  @examples[#:eval ev
(~> (dataframe (list (series '(1 2 3) #:name "a")
                     (series '(4 5 6) #:name "b")))
    (select "a" (alias (+ (col "a") (col "b")) "sum")))
(~> (dataframe (list (series '(1 2 3) #:name "a")))
    (with-columns (alias (* (col "a") 2) "double")))]}

@defproc[(cast [x (or/c Expr-ptr? series? string?)]
               [dtype (or/c dtype-spec? 'binary 'duration)])
         (or/c Expr-ptr? series?)]{
  Changes dtype. On an expression (or a column name, lifted with
  @racket[col]) it builds a cast expression, matching @tt{.cast}; on a series
  it converts eagerly and returns a series. @racket[dtype] takes the same
  spellings as @racket[series-cast], short (@racket['f64], @racket['i32],
  @racket['str]) or canonical (@racket['float64], @racket['int32],
  @racket['string]), as @racket[series]' @racket[#:dtype] does
  (@racket[dtype-spec?]), plus @racket['binary] and @racket['duration]. Any other value is a contract violation. A
  value that does not convert becomes null, except
  in a cast to an Enum, which raises as Python's default @tt{strict=True}
  does. On a series the error names the values outside the categories (the
  first ten in sorted order); on an expression it raises when the plan runs,
  with Polars' message.

  A cast to a zoned @racket['(datetime unit "Zone/Name")] keeps each
  instant: a naive datetime, or an integer count since the epoch, is read
  as UTC, as Python reads it. A cast from a zoned datetime to a naive one
  gives its UTC clock time; @racket[dt-replace-time-zone] keeps the local
  clock instead. A zone polars does not know raises, with the nearest name
  it does.

  A cast can make a date or datetime outside the years -262143 to 262142,
  which @racket[series] and @racket[lit] refuse. @racket[ref], the
  conversions and a series' printing read it as the gregor value, but for a
  datetime in a zone other than UTC, whose local clock Polars cannot give:
  @racket[ref] and the conversions raise with Polars' reason, and the series
  prints that value as a placeholder. Polars cannot print one: a dataframe
  or expression holding one prints as a placeholder with Polars' reason, and
  @racket[display-dataframe], @racket[expr->string] and a cast to
  @racket['string] raise it.

  @examples[#:eval ev
(~> (dataframe (list (series '(1 2 3) #:name "v")))
    (with-columns (cast "v" 'float64)))
(cast (series '("UA" "AA" "UA")) 'categorical)
(cast (series '(1 2 3)) 'f64)
(define-enum carriers UA AA)
(eval:error (cast (series '("UA" "B6")) carriers))
(cast (series (list (datetime 2021 3 27 12))) '(datetime microseconds "Europe/Brussels"))
(eval:error (cast (series (list (datetime 2021 3 27 12)))
                  '(datetime microseconds "Europe/Brusels")))
(define far (cast (series '(2000000000) #:dtype 'i32 #:name "d") 'date))
(ref far 0)
(dataframe (list far))
(eval:error (display-dataframe (dataframe (list far))))
(define far-zoned (cast (series '(9000000000000000000) #:dtype 'i64 #:name "k")
                        '(datetime microseconds "Europe/Brussels")))
far-zoned
(eval:error (ref far-zoned 0))]}

@defproc[(vstack [top dataframe?] [bottom dataframe?]) dataframe?]{
  Stacks the rows of @racket[bottom] beneath those of @racket[top], which must
  have the same columns in the same order and dtypes (Polars' @tt{vstack});
  otherwise it raises with Polars' reason.

  @examples[#:eval ev
(define top (dataframe (list (series '(1 2) #:name "v"))))
(vstack top (dataframe (list (series '(3) #:name "v"))))
(eval:error (vstack top (dataframe (list (series '("3") #:name "v")))))]}

@defproc[(hstack [d dataframe?] [column series?] ...) dataframe?]{
  Appends each @racket[column] to @racket[d] (Polars' @tt{hstack}). A
  column must have @racket[d]'s height and a name @racket[d] lacks.

  @examples[#:eval ev
(hstack top (series '(10 20) #:name "w"))
(eval:error (hstack top (series '(10) #:name "w")))]}

@defproc[(with-column [d dataframe?] [column series?]) dataframe?]{
  Adds @racket[column] to @racket[d], or replaces the column of its name
  (@tt{df.with_columns(s)}). A one-row @racket[column] is repeated to
  @racket[d]'s height; any other length must equal it (a frame with no
  columns takes any length).

  @examples[#:eval ev
(with-column top (series '(10 20) #:name "w"))
(with-column top (series '(0) #:name "v"))
(shape (with-column (dataframe '()) (series '(1 2) #:name "w")))
(eval:error (with-column top (series '(1 2 3) #:name "w")))]}

@deftogether[(@defproc[(head [x (or/c series? dataframe? lazyframe? Expr-ptr?)] [n size/c])
                       any/c]
              @defproc[(tail [x (or/c series? dataframe? lazyframe? Expr-ptr?)] [n size/c])
                       any/c]
              @defproc[(slice [x (or/c series? dataframe? lazyframe? Expr-ptr?)]
                              [offset int64/c]
                              [length size/c]) any/c])]{
  The first @racket[n] rows, the last @racket[n] rows, or @racket[length] rows
  starting at @racket[offset], of the same kind as @racket[x] (Polars'
  @tt{head}, @tt{tail}, @tt{slice}); a negative @racket[offset] counts from
  the end. On an expression they change the length and belong inside
  @racket[select]. The counts are unsigned and the offset signed 64-bit
  integers, as Polars takes them; a count past the end takes every row.

  @examples[#:eval ev
(define nums (dataframe (list (series '(1 2 3 4 5) #:name "v"))))
(head nums 2)
(tail nums 2)
(slice nums -2 (expt 2 40))
(~> nums (select (slice (col "v") (- (expt 2 63)) (sub1 (expt 2 64)))))
(eval:error (head nums -1))]}

@deftogether[(@defproc[(unique [x (or/c series? dataframe?)]) (or/c series? dataframe?)]
              @defproc[(drop-nulls [x (or/c series? dataframe? Expr-ptr?)]) any/c])]{
  @racket[unique] keeps one of each distinct value of a series, or one of each
  distinct row of a frame, in no promised order (Polars' @tt{unique} with its
  defaults). @racket[drop-nulls] removes a series' nulls, or every row of a
  frame that holds a null (@tt{drop_nulls}); on an expression it changes the
  length and belongs inside @racket[select]. API gap: @racket[unique] takes
  no @tt{subset}, @tt{keep} or @tt{maintain_order}, and @racket[drop-nulls]
  no @tt{subset} (#134).

  @examples[#:eval ev
(define dups
  (dataframe (list (series (list 1 1 2 polars-null) #:name "v")
                   (series '("a" "a" "b" "c") #:name "w"))))
(sort (unique dups) "v")
(series->list (drop-nulls (ref dups "v")))
(drop-nulls dups)
(eval:error (unique '(1 1 2)))]}

@defproc[(drop [d dataframe?] [names (or/c utf-8-name/c utf-8-names/c)]) dataframe?]{
  Removes the named column(s) (@tt{df.drop}). A name @racket[d] lacks, or one
  given twice, raises. Applied to a list it falls back to
  @racketmodname[racket/list]'s @racketid[drop].

  @examples[#:eval ev
(define pair (dataframe (list (series '(1) #:name "a") (series '(2) #:name "b"))))
(drop pair "a")
(eval:error (drop pair '("a" "nope")))
(drop '(1 2 3) 1)]}

@defproc[(pivot [d dataframe?]
                [#:on on utf-8-names/c]
                [#:index index utf-8-names/c]
                [#:values values utf-8-names/c]
                [#:agg agg (or/c #f 'none 'first 'sum 'min 'max 'mean 'count) 'first])
         dataframe?]{
  Spreads @racket[d] wide (@tt{df.pivot}): one row per distinct key of the
  @racket[index] columns (@racket['()] takes every column outside
  @racket[on] and @racket[values]), and one column per distinct value of
  @racket[on], sorted by value as Python's @tt{sort_columns=True}, holding the
  @racket[values] of that cell under @racket[agg]. As in Python, a
  @racket['sum] of an empty cell is 0 and @racket['count] is @tt{len};
  @racket[#f] and @racket['none] raise when a cell holds more than one value.
  A column @racket[d] lacks raises with Polars' reason.

  @examples[#:eval ev
(define sales
  (dataframe (list (series '("a" "a" "b") #:name "store")
                   (series '("q1" "q2" "q1") #:name "quarter")
                   (series '(10 20 30) #:name "sales"))))
(define by-quarter
  (sort (pivot sales #:on '("quarter") #:index '("store") #:values '("sales") #:agg 'sum)
        "store"))
by-quarter
(eval:error (pivot sales #:on '("nope") #:index '("store") #:values '("sales")))]}

@defproc[(unpivot [d dataframe?]
                  [#:on on utf-8-names/c]
                  [#:index index utf-8-names/c])
         dataframe?]{
  Melts @racket[d] long (@tt{df.unpivot}): each @racket[on] column becomes
  rows of a @racket["variable"] and a @racket["value"] column beside the
  @racket[index] columns; @racket[#:on '()] takes every column outside
  @racket[index], as Python's @tt{on=None}. A column @racket[d] lacks raises
  with Polars' reason.

  @examples[#:eval ev
(unpivot by-quarter #:on '("q1" "q2") #:index '("store"))
(eval:error (unpivot by-quarter #:on '("nope") #:index '("store")))]}

@defproc[(join [left (or/c dataframe? lazyframe?)]
               [right (or/c dataframe? lazyframe?)]
               [#:on on (or/c #f (non-empty-listof utf-8-name/c)) #f]
               [#:left-on left-on (or/c #f (non-empty-listof utf-8-name/c)) #f]
               [#:right-on right-on (or/c #f (non-empty-listof utf-8-name/c)) #f]
               [#:how how (or/c 'inner 'left 'outer 'full 'cross 'semi 'anti) 'inner])
         (or/c dataframe? lazyframe?)]{
  Joins @racket[right], of the same kind as @racket[left], onto it on the
  shared key columns @racket[#:on], or on @racket[#:left-on] /
  @racket[#:right-on] (@tt{left.join(right, ...)}). A @racket['cross] join
  takes no keys, and @racket['full] is @racket['outer]. Eager on a
  @tech{dataframe}, deferred on a @tech{lazyframe}. As in Python Polars, only
  a @racket['cross] join promises a row order; sort the result when order
  matters. Keys whose dtypes differ, a key a frame lacks, or key lists of
  different lengths raise with Polars' reason.

  @examples[#:eval ev
(define left (dataframe (list (series '("a" "b") #:name "k")
                               (series '(1 2) #:name "v"))))
(define right (dataframe (list (series '("a" "c") #:name "k")
                                (series '(10 30) #:name "w"))))
(~> (join left right #:on '("k") #:how 'left) (sort "k"))
(join left right #:on '("k") #:how 'inner)
(join left right #:on '(#"k") #:how 'inner)
(eval:error (join left (dataframe (list (series '(1 2) #:name "k"))) #:on '("k")))
(eval:error (join left right))]}

@defproc[(join-asof [left dataframe?]
                    [right dataframe?]
                    [#:on on (or/c #f utf-8-name/c) #f]
                    [#:left-on left-on (or/c #f utf-8-name/c) #f]
                    [#:right-on right-on (or/c #f utf-8-name/c) #f]
                    [#:by by (or/c #f utf-8-names/c) #f]
                    [#:left-by left-by (or/c #f utf-8-names/c) #f]
                    [#:right-by right-by (or/c #f utf-8-names/c) #f]
                    [#:strategy strategy (or/c 'backward 'forward 'nearest) 'backward]
                    [#:tolerance tolerance
                                 (or/c #f int64/c (and/c real? (not/c exact-integer?)))
                                 #f])
         dataframe?]{
  Matches each row of @racket[left] to the nearest row of @racket[right] by
  the sorted key column @racket[#:on], or @racket[#:left-on] /
  @racket[#:right-on] (@tt{left.join_asof(right, ...)}): the last one at or
  before it for @racket['backward], the first at or after it for
  @racket['forward]. @racket[#:by], or equally long @racket[#:left-by] and
  @racket[#:right-by], match within equal groups only, and a key further than
  @racket[#:tolerance] away matches nothing.

  @examples[#:eval ev
(define readings (dataframe (list (series '(1 3 5) #:name "t")
                                  (series '(100 300 500) #:name "v"))))
(define offsets (dataframe (list (series '(1 2 4) #:name "t")
                                 (series '(10 20 40) #:name "o"))))
(join-asof readings offsets #:on "t")
(join-asof readings offsets #:on "t" #:tolerance 0)
(eval:error (join-asof readings offsets #:on "t" #:left-by '("v")))]}

@defproc/arguments[csv-read-arguments (read-csv [path path-string?] dataframe?)]{
  Reads CSV into a @tech{dataframe} (@tt{pl.read_csv}). @racket[path] may be
  a glob pattern (@litchar{*}, @litchar{?}, @litchar{[...]}): every matching
  file is read, in sorted filename order, and the files must share a header;
  @racket[#:glob #f] takes the path literally, and @litchar{[[]} matches a
  literal @litchar{[} in a pattern. A relative @racket[path] is resolved
  against @racket[current-directory], whose own name is never read as a
  pattern. A directory is an error: name its files with a pattern. A
  staging file that a killed write left (@litchar{.rkt-polars-}@italic{pid}@litchar{-}@italic{n}@litchar{.partial})
  is skipped by an extension pattern such as @litchar{dir/*.csv} and read
  by a bare @litchar{dir/*}.

  A @racket[csv-char/c] is one ASCII character other than newline or
  return; the integer contracts are @tech{integer ranges}. A
  @racket[c-string/c] is a string without a NUL, and so is a
  @racket[column-name/c].
  @racket[separator] defaults to @racket[#\,]; @racket[quote-char] must
  differ from it, and @racket[#:quote-char #f] turns quoting off. An
  @racket[eol-char/c] is any ASCII character; @racket[eol-char] ends a line
  and must differ from both (a return before a newline is dropped, so
  @litchar{\r\n} files need no option).
  Lines that start with @racket[comment-prefix] are skipped. The first
  @racket[skip-rows] rows of each file are skipped, quoting respected;
  @racket[skip-lines] skips lines instead, ignoring quotes, and only one of
  the two may be set. @racket[skip-rows-after-header] skips rows after the
  header, and @racket[n-rows] caps the rows read.
  A field equal to one of @racket[null-values] reads as null; given as an
  association list of column names and markers, each marker applies to its
  column only, and naming a column the file lacks is
  an error. A missing field reads as null, or as @racket[""] in a string
  column with @racket[#:missing-utf8-is-empty-string #t]. Column types
  are inferred from the first @racket[infer-schema-length] rows: @racket[#f]
  reads every row, and @racket[0], or @racket[#:infer-schema #f], makes every
  column a string. A count whose reservation, 24 bytes a row, exceeds the
  host's memory (a container's cgroup limit where one is set, or
  @tt{POLARS_OVERRIDE_TOTAL_MEMORY} bytes, a malformed value counting as 0),
  or above the rows a local input could hold (one a byte, after the most its
  compression can expand), reads every row, as @racket[#f] does. Deciding the
  second stats the inputs when the read or scan is built, so a pipe, a
  device or a file created after @racket[scan-csv] never bounds the count,
  and a count past a file's size then reads every row even if the file
  grows (or reports a size of 0 though it has content). Polars reserves
  room for the count before it reads, so a smaller count that is still
  enormous can exhaust memory and abort the process.
  @racket[schema-overrides] fixes the named columns' types. A
  @racket[csv-dtype/c] is any spelling @racket[series]' @racket[#:dtype]
  accepts except a duration and @racket['null], which Polars cannot read
  from CSV, an Enum and a zoned datetime (#170); API gap: read the column as
  @racket['categorical], @racket['string] or a naive datetime and
  @racket[cast] it. Each column
  appears at most once (@racket[distinct-names?]), and naming a column the
  file lacks is an error. With
  @racket[#:ignore-errors #t] a field that does not parse reads as null. @racket[#:try-parse-dates #t] reads ISO
  dates, times of day and datetimes as @racket['date], @racket['time] and
  @racket['datetime] columns, and datetimes with a UTC offset as
  @racket['(datetime microseconds "UTC")], as Python does.
  @racket[#:decimal-comma #t] reads
  @litchar{1,5} as @racket[1.5]. @racket['utf8-lossy] replaces invalid UTF-8 with
  U+FFFD. A line with more fields than the header is an error, unless
  @racket[#:truncate-ragged-lines #t] drops the extra fields; an empty file is
  an error, unless @racket[#:raise-if-empty #f] reads it as an empty frame.

  @racket[new-columns] renames the file's first columns, header or
  @racket["column_1"]-style names alike; more names than the file has
  columns, or a name that ends up twice, is an error. @racket[columns] reads
  only the named columns, or those at the given zero-based positions, in the
  file's order; the empty list reads them all. @racket[row-index-name] adds
  a first column, @racket['uint32], numbering the rows from
  @racket[row-index-offset]; a name the file already uses is an error, and so
  is a row number past @racket[#xFFFFFFFF]. Every keyword that names a
  column --- @racket[columns], @racket[schema-overrides], a per-column
  @racket[null-values] --- names it as @racket[new-columns] leaves it, and a
  marker so named also counts when the column's type is inferred.

  A gzip, zlib or zstd file is decompressed as it is read, judged by its
  first four bytes, so a plain file that starts like a zlib stream (a header
  beginning @litchar{x^}) fails to read or reads as garbage; a UTF-8 byte
  order mark at the start of the file avoids it. API gaps: no
  @tt{schema}, @tt{with_column_names}, @tt{include_file_paths} or
  @tt{missing_columns}.

  The result is @racket[(collect (scan-csv path ....))] with the same
  keywords but @racket[#:columns], which @racket[scan-csv] lacks:
  @racket[select] from the plan instead. A single file is read eagerly
  rather than through a plan, which is faster. One check is
  @racket[read-csv]'s own. When @racket[separator] is
  @racket[#f], @racket[new-columns] and @racket[columns] are empty and the
  file reads as one column, a row index aside, whose header splits on a tab, @litchar{;} or
  @litchar{|}, @racket[read-csv] raises an error naming the separator to
  pass --- unless the first row is not a string, or splits into a different
  number of fields. Passing a @racket[separator], even @racket[#\,], turns
  the check off.

  A failure names the operation, the path and the cause: the operating
  system's for a file that cannot be opened, Polars' own for input it cannot
  parse.

  The examples read @filepath{flights.tsv}, 102 rows of the nycflights13 data
  with @litchar{NA} for a missing value. Without @racket[#:separator] the
  separator check stops the read; with it, the first @litchar{NA} fails to
  parse, and @racket[#:null-values] fixes that:

  @examples[#:eval ev
(eval:error (read-csv "flights.tsv"))
(eval:error (read-csv "flights.tsv" #:separator #\tab))
(define flights (read-csv "flights.tsv" #:separator #\tab #:null-values "NA"))
(shape flights)
(null-count (ref flights #:columns "dep_delay"))
(~> (read-csv "flights.tsv" #:separator #\tab #:null-values '("NA" ""))
    (ref #:columns "arr_delay")
    null-count)]

  Failures. A missing file or an unwritable path reports the operating
  system's reason; a file in the wrong format reports Polars':

  @examples[#:eval ev #:label #f
(eval:error (read-csv "/no/such/file.csv"))
(define small (dataframe (list (series '(1 2) #:name "v"))))
(eval:error (write-parquet small "/no/such/dir/out.parquet"))]

  Here @racket[not-parquet] is a path in the temporary directory:

  @examples[#:eval ev #:hidden
(define not-parquet (build-path (find-system-path 'temp-dir) "polars-not-parquet.csv"))]

  @examples[#:eval ev #:label #f
(write-csv small not-parquet)
(eval:error (read-parquet not-parquet))
(eval:error (read-ndjson not-parquet))]

  @examples[#:eval ev #:hidden
(delete-file not-parquet)]

  Types. @racket[#:ignore-errors] turns what does not parse into nulls;
  @racket[#:infer-schema-length] widens or narrows the rows types are
  inferred from; @racket[#:schema-overrides] and @racket[#:try-parse-dates]
  set them outright. An override for a column the file lacks is an error:

  @examples[#:eval ev #:label #f
(~> (read-csv "flights.tsv" #:separator #\tab #:ignore-errors #t)
    (ref #:columns "dep_delay")
    null-count)
(~> (read-csv "flights.tsv" #:separator #\tab #:infer-schema-length #f)
    (ref #:columns "dep_delay")
    dtype)
(~> (read-csv "flights.tsv" #:separator #\tab #:infer-schema-length 0)
    (ref #:columns "year")
    dtype)
(~> (read-csv "flights.tsv" #:separator #\tab #:null-values "NA"
              #:try-parse-dates #t
              #:schema-overrides '(("dep_delay" . f64) ("flight" . int32)))
    (select "dep_delay" "flight" "time_hour")
    (tail 3))
(eval:error (read-csv "flights.tsv" #:separator #\tab
                      #:schema-overrides '(("dep_dealy" . f64))))]

  Layout. @filepath{notes.csv} has a comment line, @litchar{;} between fields
  and @litchar{'} around a field that holds one; @filepath{latin1.csv} is not
  UTF-8:

  @examples[#:eval ev #:label #f
(read-csv "notes.csv" #:separator #\; #:comment-prefix "#" #:quote-char #\')
(eval:error (read-csv "notes.csv" #:separator #\; #:comment-prefix "#"))
(read-csv "parts/part-1.csv" #:has-header #f #:skip-rows 1)
(~> (read-csv "flights.tsv" #:separator #\tab #:null-values "NA" #:n-rows 2)
    (select "carrier" "flight" "dep_delay"))
(eval:error (read-csv "latin1.csv"))
(read-csv "latin1.csv" #:encoding 'utf8-lossy)]

  Files. A pattern reads every match, in filename order; one that matches
  nothing, a literal path with @racket[#:glob #f], and a directory are
  errors:

  @examples[#:eval ev #:label #f
(read-csv "parts/*.csv")
(eval:error (read-csv "parts/*.tsv"))
(eval:error (read-csv "parts/part-?.csv" #:glob #f))
(eval:error (read-csv "parts"))]

  Columns. @racket[#:columns] picks columns by name or position, in the
  file's order; @racket[#:new-columns] renames the first ones, and
  @racket[#:row-index-name] numbers the rows:

  @examples[#:eval ev #:label #f
(read-csv "flights.tsv" #:separator #\tab #:null-values "NA"
          #:columns '("carrier" "flight" "dep_delay")
          #:row-index-name "row" #:row-index-offset 1 #:n-rows 3)
(read-csv "flights.tsv" #:separator #\tab #:columns '(9 10) #:n-rows 2)
(eval:error (read-csv "flights.tsv" #:separator #\tab #:columns '(42)))
(read-csv "parts/part-1.csv" #:has-header #f #:skip-rows 1
          #:new-columns '("from" "to" "delay"))
(eval:error (read-csv "parts/part-1.csv" #:new-columns '("a" "b" "c" "d")))
(eval:error (read-csv "parts/part-1.csv" #:row-index-name "origin"))]

  Messy files. @filepath{stations.csv} opens with a line that is not data
  and holds a quote, separates fields with @litchar{;}, writes decimals
  with a comma, marks a missing temperature @litchar{-} and missing rain
  @litchar{n/a}, and has a line with a field too many. The note
  @litchar{-} is text, so the markers are per column:

  @examples[#:eval ev #:label #f
(eval:error (read-csv "stations.csv" #:skip-lines 1 #:separator #\;))
(define stations
  (read-csv "stations.csv" #:skip-lines 1 #:separator #\; #:decimal-comma #t
            #:null-values '(("temp" . "-") ("rain" . "n/a"))
            #:truncate-ragged-lines #t #:try-parse-dates #t))
stations
(~> (read-csv "stations.csv" #:skip-lines 1 #:separator #\; #:decimal-comma #t
              #:null-values '(("temp" . "-") ("rain" . "n/a"))
              #:truncate-ragged-lines #t #:missing-utf8-is-empty-string #t)
    (select "station" "note"))
(eval:error (read-csv "stations.csv" #:skip-lines 1 #:separator #\;
                      #:null-values '(("temperature" . "-"))))
(read-csv "parts/part-1.csv" #:skip-rows-after-header 1)
(~> (read-csv "flights.tsv" #:separator #\tab #:infer-schema #f)
    (ref #:columns "year")
    dtype)]

  Line ends and empty files. @filepath{eol.csv} ends each line with
  @litchar{;}, and @racket[nothing] is an empty file in the temporary
  directory:

  @examples[#:eval ev #:hidden
(define nothing (build-path (find-system-path 'temp-dir) "polars-doc-nothing.csv"))
(call-with-output-file nothing #:exists 'replace void)]

  @examples[#:eval ev #:label #f
(read-csv "eol.csv" #:eol-char #\;)
(collect (scan-csv "eol.csv" #:eol-char #\; #:row-index-name "row" #:row-index-offset 1))
(eval:error (read-csv nothing))
(read-csv nothing #:raise-if-empty #f)]

  @examples[#:eval ev #:hidden
(delete-file nothing)]}

@defproc/arguments[csv-scan-arguments (scan-csv [path path-string?] lazyframe?)]{
  Starts a @tech{lazyframe} plan from CSV without reading it
  (@tt{pl.scan_csv}); the keywords are @racket[read-csv]'s but
  @racket[#:columns], which @racket[select] replaces. @racket[collect]
  runs the plan, and that is where a file that cannot be read, or a glob
  pattern that matches no file, is reported, and so is a row number past
  @racket[#xFFFFFFFF]. A staging file that a killed write left in a
  directory makes a read of that directory fail (``different file
  extensions''). Two keywords read the header
  here instead, and so report a file that cannot be read at once:
  @racket[schema-overrides], to report a column it names that the header
  lacks, and @racket[new-columns], to rename the header, which also reports
  a @racket[row-index-name] that one of the new names takes. The separator
  check does not apply, and a directory reads every file in it.

  @examples[#:eval ev
(~> (scan-csv "flights.tsv" #:separator #\tab #:null-values "NA")
    (filter (> (col "dep_delay") 30))
    (select "carrier" "dep_delay")
    collect)
(~> (scan-csv "parts/*.csv") (group-by "origin") (agg (sum "dep_delay")) collect)
(shape (collect (scan-csv "flights.tsv")))
(define plan (scan-csv "/no/such/file.csv"))
(eval:error (collect plan))
(define no-match (scan-csv "parts/*.tsv"))
(eval:error (collect no-match))
(eval:error (scan-csv "flights.tsv" #:separator #\tab
                      #:schema-overrides '(("dep_dealy" . f64))))
(~> (scan-csv "parts/part-1.csv" #:new-columns '("from" "to") #:row-index-name "row")
    (filter (> (col "dep_delay") 3))
    collect)
(eval:error (scan-csv "/no/such/file.csv" #:new-columns '("from" "to")))]}

@defproc/arguments[csv-write-arguments (write-csv [frame dataframe?] [path path-string?] void?)]{
  Writes @racket[frame] to @racket[path] as CSV (@tt{df.write_csv}), replacing
  the file. The header row comes first unless @racket[#:include-header #f],
  after a UTF-8 byte order mark with @racket[#:include-bom #t].
  @racket[separator] and @racket[quote-char] are @racket[csv-char/c]s that
  must differ; @racket[line-terminator] ends every row; a null is written as
  @racket[null-value]. @racket[quote-style] quotes a field only when it
  holds the separator, the quote or a line end (@racket['necessary]),
  always, when it is not a number (@racket['non-numeric]), or never, which
  can write a file that does not read back. @racket[batch-size] is the rows
  each thread formats at a time; a batch larger than @racket[frame] writes
  it in one.

  @racket[datetime-format], @racket[date-format] and @racket[time-format]
  are @hyperlink["https://docs.rs/chrono/latest/chrono/format/strftime/index.html"]{chrono}
  format strings, by default ISO 8601 at the column's precision; a zoned
  datetime is written as its local time and UTC offset,
  @tt{2021-03-27T12:00:00.000000+0100}, as Python does.
  @racket[float-precision] fixes the digits after the decimal point; a
  @racket[float-precision/c] is at most 65535, the most Rust formats;
  @racket[float-scientific] writes every float in scientific notation
  (@racket[#t]), none (@racket[#f]), or as Polars does by default
  (@racket['auto]): the shortest digits that read back
  exactly, in scientific notation for very small or large magnitudes.
  @racket[#:decimal-comma #t] writes @litchar{1,5}, quoting it when the
  separator is a comma.

  An existing file is replaced atomically, keeping its permission bits but
  not its owner, ACLs, extended attributes or hard links; the directory
  must be writable. A failure names the path and the cause, the operating
  system's for a path that cannot be created and Polars' for a value it
  cannot format, and leaves an existing file as it was. API gap: no
  compressed output (@tt{compression}).

  @examples[#:eval ev #:hidden
(require racket/file)
(define out (build-path (find-system-path 'temp-dir) "polars-doc-out.csv"))]
  Here @racket[out] is a path in the temporary directory, and
  @racket[stations] the frame read above:

  @examples[#:eval ev #:label #f
(write-csv stations out #:separator #\; #:decimal-comma #t #:null-value "-"
           #:date-format "%d.%m.%Y" #:time-format "%H:%M")
(display (file->string out))
(write-csv (select stations "station" "note") out #:include-header #f
           #:quote-style 'always #:line-terminator "\r\n")
(file->string out)
(write-csv (select stations "station" "temp") out #:float-precision 2)
(display (file->string out))
(write-csv (select stations "station" "temp") out #:float-scientific #t)
(display (file->string out))
(write-csv (~> (read-csv "flights.tsv" #:separator #\tab #:null-values "NA"
                         #:try-parse-dates #t #:n-rows 2)
               (select "carrier" "flight" "time_hour"))
           out #:datetime-format "%Y-%m-%dT%H:%M" #:quote-style 'non-numeric
           #:include-bom #t #:batch-size 1)
(file->string out)
(eval:error (write-csv stations out #:date-format "%H"))
(eval:error (write-csv stations "/no/such/dir/out.csv"))]

  @examples[#:eval ev #:hidden
(delete-file out)]}

@defproc/arguments[parquet-read-arguments (read-parquet [path path-string?] dataframe?)]{
  Reads Parquet into a @tech{dataframe} (@tt{pl.read_parquet}): it is
  @racket[(collect (scan-parquet path ....))] with the same keywords, then
  @racket[columns]. @racket[path] is a glob pattern: the matching files stack
  in sorted filename order, and one that matches nothing is an error;
  @racket[#:glob #f] takes it literally. A directory reads every file in it
  and adds its @litchar{key=value} subdirectory names as columns; a single
  file or a pattern adds none, and neither does a directory whose own path
  holds @litchar{[}, @litchar{*} or @litchar{?}. A relative @racket[path] is
  resolved against @racket[current-directory], whose own name is never read
  as a pattern. A staging file that a killed write left
  (@litchar{.rkt-polars-}@italic{pid}@litchar{-}@italic{n}@litchar{.partial})
  is skipped by an extension pattern such as @litchar{dir/*.parquet}, read
  by a bare @litchar{dir/*}, and makes a read of the directory fail.

  @racket[columns] picks columns by name, or by position from 0 (negative
  counts from the end), in the order given; a name the file lacks, a position out of
  range or a column picked twice is an error. A name is matched literally.
  @racket[n-rows] caps the rows read. @racket[row-index-name] adds a first
  column numbering the rows from @racket[row-index-offset]; a row number
  past @racket[#xFFFFFFFF] is an error.
  @racket[include-file-paths] adds a column of that name holding each row's
  file as a complete path. When the files a pattern matches differ, a file
  that lacks a column of the first is an error unless
  @racket[#:missing-columns 'insert], which fills it with nulls.
  @racket[parallel], a @racket[parquet-parallel/c] (@racket['auto],
  @racket['columns], @racket['row-groups], @racket['prefiltered] or
  @racket['none]), sets how the reader divides the work (over columns, row
  groups, both after evaluating a pushed-down filter, or not at all),
  @racket[#:use-statistics #f] stops it skipping row groups by their
  statistics,
  @racket[low-memory] trades speed for memory and @racket[rechunk] makes
  each column contiguous; none of the four changes the result.

  Categorical, Enum and Decimal columns keep their dtypes
  (@secref["ref-categorical"]), and a datetime column its unit and time
  zone. A file Polars cannot read raises
  @racket[exn:fail] with Polars' reason, even where Polars itself panics.
  API gaps: no @tt{schema}, @tt{extra_columns}, @tt{use_pyarrow} or hive
  options.

  @examples[#:eval ev #:hidden
(require racket/file)
(define parquet-dir (make-temporary-directory "polars-doc-~a"))
(for ([i '(1 2 3)])
  (write-parquet (read-csv (format "parts/part-~a.csv" i))
                 (build-path parquet-dir (format "part-~a.parquet" i))))
(define produce (read-parquet "produce.parquet"))
(define mixed-dir (build-path parquet-dir "mixed"))
(make-directory mixed-dir)
(write-parquet produce (build-path mixed-dir "a.parquet"))
(write-parquet (select produce "item") (build-path mixed-dir "b.parquet"))]
  @examples[#:eval ev
(read-parquet "produce.parquet")
(read-parquet (build-path parquet-dir "*.parquet"))
(read-parquet "flights.parquet" #:columns '("carrier" "dep_delay") #:n-rows 3)
(read-parquet "flights.parquet" #:columns '(0 1 -1) #:n-rows 2
              #:row-index-name "row" #:row-index-offset 1)
(column-names (read-parquet "produce.parquet" #:include-file-paths "file"))
(shape (read-parquet "flights.parquet" #:parallel 'row-groups #:use-statistics #f
                     #:low-memory #t #:rechunk #t))
(shape (read-parquet "produce.parque?"))
(eval:error (read-parquet "produce.parque?" #:glob #f))
(eval:error (read-parquet "produce.parquet" #:columns '("item" "colour")))
(eval:error (parameterize ([current-directory parquet-dir])
               (read-parquet "mixed/*.parquet")))
(parameterize ([current-directory parquet-dir])
  (read-parquet "mixed/*.parquet" #:missing-columns 'insert))]}

@defproc/arguments[parquet-scan-arguments (scan-parquet [path path-string?] lazyframe?)]{
  Starts a @tech{lazyframe} plan from Parquet without reading it
  (@tt{pl.scan_parquet}); the keywords are @racket[read-parquet]'s, without
  @racket[#:columns] (@racket[select] instead) and with @racket[cache],
  which keeps what the scan reads for a plan that uses it more than once.
  @racket[collect] runs the plan, and that is where a file that cannot be
  read, a pattern that matches nothing, or a row number past
  @racket[#xFFFFFFFF] is reported. A staging file is treated as by
  @racket[read-parquet]. Polars reads only
  the columns the plan uses, and skips row groups its filter rules out;
  @racket[explain] shows both.

  @examples[#:eval ev
(~> (scan-parquet "flights.parquet")
    (filter (> (col "dep_delay") 20))
    (select "carrier" "dep_delay")
    collect)
(collect (scan-parquet (build-path parquet-dir "part-*.parquet") #:n-rows 3))
(collect (scan-parquet "produce.parquet" #:cache #f #:row-index-name "row"))
(eval:error (scan-parquet "flights.parquet" #:parallel 'row_groups))]}

@defproc/arguments[parquet-write-arguments (write-parquet [frame dataframe?] [path path-string?] void?)]{
  Writes @racket[frame] to Parquet (@tt{df.write_parquet}).
  @racket[compression], a @racket[parquet-compression/c] (@racket['uncompressed],
  @racket['snappy], @racket['gzip], @racket['brotli], @racket['lz4] or
  @racket['zstd]), picks the codec; @racket[compression-level] sets its
  level, within 0 to 9 for @racket['gzip] (default 6), 0 to 11 for
  @racket['brotli] (default 1) and 1 to 22 for @racket['zstd] (default 3),
  and the other codecs ignore it. @racket[statistics], a
  @racket[parquet-statistics/c], writes each column chunk's minimum, maximum
  and null count by default; @racket[#f] writes none, @racket['full] also
  writes the distinct count (for boolean columns), and a list names the ones
  to write: @racket['min], @racket['max] and @racket['null-count], plus
  @racket['distinct-count] if wanted. @racket[row-group-size] puts that many
  rows in each row group, the last taking the rest; by default, or with
  @racket[0], Polars picks it. @racket[data-page-size] sets the bytes a data
  page aims for (default 1 MiB). A datetime's time zone is kept in the
  column's type. It replaces a file as @racket[write-csv] does. API gaps: @tt{partition_by}, @tt{metadata}, @tt{mkdir}.

  @examples[#:eval ev
(define out (build-path parquet-dir "produce.parquet"))
(write-parquet produce out #:compression 'gzip #:compression-level 9 #:statistics #f)
(read-parquet out)
(write-parquet produce out #:compression 'lz4 #:row-group-size 2
               #:statistics '(min max null-count distinct-count) #:data-page-size 4096)
(read-parquet out)
(eval:error (write-parquet produce out #:compression-level 30))
(eval:error (write-parquet produce out #:statistics '(null-count)))
(eval:error (write-parquet produce "/no/such/dir/out.parquet"))]}

@deftogether[(@defproc/arguments[json-arguments (read-json [path path-string?] dataframe?)]
              @defproc[(write-json [d dataframe?] [path path-string?]) void?])]{
  Read a file holding one JSON array of objects into a @tech{dataframe}
  (@tt{pl.read_json}), and write a dataframe as one (@tt{df.write_json}).
  A lone object reads as one row. @racket[path] is literal; a directory is
  an error. A gzip, zlib or zstd file is decompressed first, recognised by
  its first bytes.

  Column types are inferred from the first @racket[infer-schema-length]
  objects, or from all of them for @racket[#f]; a key first seen later is an
  error. A later value of another JSON type converts where Polars can (a
  float truncates to an integer, a boolean reads as 0 or 1, a number out of
  the type's range reads as null) and is an error otherwise.
  @racket[schema] gives the columns in order: other keys are skipped and a
  column the file lacks reads as nulls. @racket[schema-overrides] retypes
  columns of the file or of @racket[schema]; naming any other column is an
  error. A @racket[json-schema/c] is a list of @racket[(cons name dtype)]
  pairs with distinct names, a name a string without a NUL
  (@racket[column-name/c]) and a dtype any @racket[series]
  @racket[#:dtype] spelling but an Enum. A string reads as the date,
  datetime or time the schema asks for, and as null where it does not
  parse.

  @racket[write-json] writes temporal values as strings, Categorical and
  Enum values as their names, and NaN and the infinities as @tt{null}, so
  reading them back needs a schema; a binary column is an error. It
  replaces a file as @racket[write-csv] does.

  @racketmodname[json] provides a @racket[read-json] and @racket[write-json]
  too, so @racket[(require polars json)] fails with ``identifier already
  required''. Rename or leave out @racketmodname[json]'s pair:

  @racketblock[
  (require polars (prefix-in js: json))
  (require polars (except-in json read-json write-json))
  ]

  @examples[#:eval ev #:hidden
(require racket/file)
(define json-dir (make-temporary-directory "polars-doc-~a"))
(define path (build-path json-dir "frame.json"))]
  @examples[#:eval ev
(define df (dataframe (list (series '(1 2 3) #:name "foo")
                            (series (list polars-null "bak" "baz") #:name "bar"))))
(write-json df path)
(file->string path)
(read-json path)
(read-json "stations.json")
(read-json "stations.json"
           #:schema '(("day" . date) ("station" . categorical) ("reading" . f32)))
(~> (read-json "stations.json" #:schema-overrides '(("day" . date)))
    (select "day" "reading"))
(~> (read-json "stations.json" #:schema '(("day" . datetime))) (head 1))
(~> (read-json "stations.json" #:schema-overrides '(("reading" . i64)))
    (select "station" "reading"))
(eval:error (read-json "stations.json" #:infer-schema-length 1))
(eval:error (read-json "stations.json" #:schema-overrides '(("dya" . date))))]
  @examples[#:eval ev #:hidden
(delete-directory/files json-dir)]}

@deftogether[(@defproc/arguments[ndjson-arguments (read-ndjson [path path-string?] dataframe?)]
              @defproc/arguments[ndjson-arguments (scan-ndjson [path path-string?] lazyframe?)])]{
  Read newline-delimited JSON, one object a line, into a @tech{dataframe}
  (@tt{pl.read_ndjson}), or start a @tech{lazyframe} plan from it
  (@tt{pl.scan_ndjson}); @racket[read-ndjson] is
  @racket[(collect (scan-ndjson path ....))]. @racket[path] is a glob
  pattern: the matching files stack in sorted filename order, and a pattern
  matching nothing is an error, which @racket[scan-ndjson] leaves to
  @racket[collect]. A directory reads every file in it, and they must share
  one extension. A literal @litchar{[}, @litchar{*} or @litchar{?} in a
  file name is spelled @litchar{[[]}, @litchar{[*]} or @litchar{[?]}.

  Column types are inferred from the first @racket[infer-schema-length]
  lines, or from all of them for @racket[#f]. A key first seen later is
  left out, and a value that does not parse as its column's type is an
  error, or null with @racket[#:ignore-errors #t]. @racket[schema] and
  @racket[schema-overrides] work as for @racket[read-json], an override
  applying even with a schema; @racket[scan-ndjson] reports a bad override
  at once. An @racket[ndjson-schema/c] is a @racket[json-schema/c] whose
  dtypes are a boolean, a 32- or 64-bit integer, a float, a string, a date,
  a datetime, a categorical or @racket['null]; a @racket['null] column
  holds no value, and a value in the file for it is an error, as in Python.

  @racket[n-rows] caps the rows read. @racket[row-index-name] adds a first
  @racket['uint32] column of row numbers from @racket[row-index-offset];
  @racket[include-file-paths] adds a last column holding each row's file;
  the two name different columns. @racket[rechunk] gathers the result into
  one chunk. Polars ignores @racket[batch-size] and @racket[low-memory].
  A gzip, zlib or zstd file is decompressed as it is read, recognised by
  its first bytes rather than its name.

  @examples[#:eval ev #:hidden
(require racket/file)
(define nd-dir (make-temporary-directory "polars-doc-~a"))
(for ([i '(1 2 3)])
  (write-ndjson (read-csv (format "parts/part-~a.csv" i))
                (build-path nd-dir (format "part-~a.ndjson" i))))]
  @examples[#:eval ev
(read-ndjson "stations.ndjson")
(~> (scan-ndjson "stations.ndjson")
    (filter (> (col "reading") 3))
    (select "station" "reading")
    collect)
(read-ndjson (build-path nd-dir "part-*.ndjson") #:n-rows 4 #:row-index-name "row")
(column-names (read-ndjson "stations.ndjson" #:include-file-paths "file"))
(read-ndjson "stations.ndjson" #:schema '(("station" . str) ("extra" . null)))
(eval:error (read-ndjson "stations.ndjson" #:schema '(("station" . str) ("note" . null))))
(eval:error (read-ndjson "stations.ndjson" #:infer-schema-length 1))
(~> (read-ndjson "stations.ndjson" #:infer-schema-length 1 #:ignore-errors #t)
    (select "station" "reading"))
(eval:error (scan-ndjson "stations.ndjson" #:schema-overrides '(("dya" . date))))
(eval:error (read-ndjson (build-path nd-dir "*.json")))]
  @examples[#:eval ev #:hidden
(delete-directory/files nd-dir)]}

@defproc/arguments[ndjson-writer-arguments (write-ndjson [d dataframe?] [path path-string?] void?)]{
  Write @racket[d] as newline-delimited JSON, one object a line
  (@tt{df.write_ndjson}), with values written as @racket[write-json] writes
  them; a binary column is an error. @racket[compression] gzips or
  zstd-compresses the whole file at @racket[compression-level], 0 to 9 for
  gzip and 1 to 22 for zstd, or the codec's default for @racket[#f]; a
  level without a codec is a contract error. Unless
  @racket[check-extension] is @racket[#f], the path must end in
  @filepath{.gz} for gzip and @filepath{.zst} for zstd, and in neither for
  an uncompressed file. It replaces a file as @racket[write-csv] does.

  @examples[#:eval ev #:hidden
(define nd-dir (make-temporary-directory "polars-doc-~a"))]
  @examples[#:eval ev
(define small (dataframe (list (series '(1 2) #:name "a"))))
(write-ndjson small (build-path nd-dir "small.ndjson"))
(file->string (build-path nd-dir "small.ndjson"))
(write-ndjson small (build-path nd-dir "small.ndjson.gz") #:compression 'gzip)
(read-ndjson (build-path nd-dir "small.ndjson.gz"))
(eval:error (write-ndjson small (build-path nd-dir "small.ndjson.zst")))
(eval:error (write-ndjson small (build-path nd-dir "small.ndjson.zst")
                          #:compression 'zstd #:compression-level 30))]
  @examples[#:eval ev #:hidden
(delete-directory/files nd-dir)]}

@deftogether[(@defproc[(lazy [d dataframe?]) lazyframe?]
              @defproc[(collect [lf lazyframe?]) dataframe?])]{
  @racket[lazy] turns a dataframe into a @tech{lazyframe} — a plan that
  @racket[select], @racket[with-columns], @racket[filter] and the other
  fluent operations extend without running anything — and @racket[collect]
  executes the plan and returns the resulting dataframe. A plan that cannot
  run, such as one reading a column the frame lacks, is reported by
  @racket[collect] with Polars' reason.

  @examples[#:eval ev
(define four (dataframe (list (series '(1 2 3 4) #:name "v"))))
(~> four lazy (filter (> (col "v") 2)) collect)
(eval:error (~> four lazy (filter (> (col "nope") 2)) collect))]}

@defproc[(explain [lf lazyframe?]
                  [#:optimized optimized boolean? #t]
                  [#:format format (or/c 'plain 'tree) 'plain])
         string?]{
  Returns the plan @racket[lf] would run, as text (@tt{lf.explain()}): the
  optimised plan, or with @racket[#:optimized #f] the plan as written;
  @racket['tree] draws it as a tree. Reading the optimised plan from the
  bottom up, a filter and a column selection that Polars pushed into a scan
  appear in the scan itself, as its @tt{SELECTION} and its
  @tt{PROJECT} count. A plan that cannot resolve, such as one naming a
  column its source lacks, is an error.

  @examples[#:eval ev
(define late
  (~> (scan-parquet "flights.parquet")
      (filter (> (col "dep_delay") 20))
      (select "carrier" "dep_delay")))
(displayln (explain late #:optimized #f))
(displayln (explain late))
(displayln (explain (select (lazy produce) "item") #:format 'tree))
(eval:error (explain (select (lazy produce) "colour")))
(eval:error (explain late #:format 'dot))]}

@deftogether[(@defproc[(group-by [d (or/c dataframe? lazyframe?)] [key (or/c string? Expr-ptr?)] ...+)
                       grouped?]
              @defproc[(agg [g grouped?] [agg-expr Expr-ptr?] ...) (or/c dataframe? lazyframe?)]
              @defproc[(grouped? [v any/c]) boolean?])]{
  @racket[group-by] captures @racket[d] and one or more group keys in a deferred
  @racket[grouped] handle — no work happens yet — so it threads cleanly.
  @racket[agg] consumes the handle, computing the aggregation expressions per
  group in a single pass, and returns a dataframe with one row per group. The
  split mirrors @tt{df.group_by("g").agg(...)}; the row order of the result is
  not guaranteed.

  @examples[#:eval ev
(~> (dataframe (list (series '("x" "y" "x") #:name "k")
                     (series '(1 2 3) #:name "v")))
    (group-by "k")
    (agg (alias (sum "v") "total")))]}

@defproc[(over [e (or/c Expr-ptr? string?)] [key (or/c Expr-ptr? string?)] ...+) Expr-ptr?]{
  A window function (@tt{Expr.over}): @racket[e] is computed within each
  group of the @racket[key]s — column names or expressions, as
  @racket[group-by] takes them — and broadcast back onto the group's rows
  rather than reduced to one row per group, so it belongs in
  @racket[with-columns] where @racket[agg] would collapse it. An aggregate
  is repeated on every row of its group; an expression that keeps one value
  per row, such as @racket[rank], is computed within the group and each
  value lands on the row it came from. Only Polars' default
  @tt{group_to_rows} mapping is exposed.

  @examples[#:eval ev
(define kv (dataframe (list (series '("x" "y" "x") #:name "k")
                            (series '(1 2 3) #:name "v"))))
(~> kv (group-by "k") (agg (alias (sum "v") "total")))
(~> kv (with-columns (~> (col "v") sum (over "k") (alias "total"))))
(define khv (dataframe (list (series '("a" "a" "a" "b") #:name "k")
                             (series '("x" "y" "x" "x") #:name "h")
                             (series '(1 2 3 4) #:name "v"))))
(~> khv (with-columns (~> (col "v") sum (over "k" "h") (alias "total"))
                      (~> (col "v") mean (over (col "k")) (alias "mean"))
                      (~> (col "v") (rank #:descending #t) (over "k") (alias "rank"))
                      (~> (col "v") max (over (> (col "v") 1)) (alias "band_max"))))
(eval:error (over (col "v")))]}

@deftogether[(@defproc[(rank [x (or/c Expr-ptr? string?)]
                             [#:method method (or/c 'average 'min 'max 'dense 'ordinal) 'average]
                             [#:descending descending boolean? #f]
                             [#:seed seed (or/c uint64/c #f) #f])
                       Expr-ptr?]
              @defproc[(gather [x (or/c Expr-ptr? string?)]
                               [indices (or/c Expr-ptr? series?
                                              (listof (or/c int64/c polars-null?)))])
                       Expr-ptr?])]{
  Ordering within a column (@tt{.rank}, @tt{.gather}); @racket[sort-by] is
  documented with the other sorts. @racket[rank] numbers each
  value by its place in the sorted order, ties resolved by
  @racket[#:method]; the result is @racket['uint32], or @racket['float64]
  for @racket['average]. @racket[gather] picks values by position, and a
  @racket[polars-null] position gives a null. Each
  lifts a column name with @racket[col], and each is computed per group
  under @racket[over].

  @examples[#:eval ev
(define scores (dataframe (list (series '("a" "b" "c" "d") #:name "name")
                                (series '(30 10 30 20) #:name "score"))))
(~> scores
    (with-columns (~> (col "score") (rank #:method 'dense #:descending #t) (alias "dense"))
                  (~> (col "score") (rank #:method 'ordinal) (alias "ordinal"))))
(~> scores (select (gather "name" '(3 0))))
(~> scores (select (gather "score" (list 0 polars-null))))
(eval:error (rank "score" #:method 'first))]}

@deftogether[(@defproc[(shift [x (or/c Expr-ptr? string?)]
                              [#:n n int64/c 1]
                              [#:fill-value fill-value any/c #f])
                       Expr-ptr?]
              @defproc[(diff [x (or/c Expr-ptr? string?)]
                             [#:n n int64/c 1]
                             [#:null-behavior null-behavior (or/c 'ignore 'drop) 'ignore])
                       Expr-ptr?])]{
  @racket[shift] moves each value @racket[n] rows down, or up for a negative
  @racket[n], and fills the rows it vacates with null, or with
  @racket[fill-value] lifted by @racket[lit] (@tt{.shift}). @racket[diff] is
  each value less the one @racket[n] rows before it (@tt{.diff});
  @racket['drop] removes the leading nulls that leaves.

  @examples[#:eval ev
(define steps (dataframe (list (series '(1 3 6 10) #:name "v"))))
(select steps
        (alias (shift "v") "down")
        (alias (shift "v" #:n -1 #:fill-value 0) "up")
        (alias (diff "v") "change"))
(select steps (diff "v" #:null-behavior 'drop))
(eval:error (shift "v" #:n (expt 2 63)))]}

@deftogether[(@defproc[(forward-fill [x (or/c Expr-ptr? string?)]
                                     [#:limit limit (or/c uint32/c #f) #f])
                       Expr-ptr?]
              @defproc[(backward-fill [x (or/c Expr-ptr? string?)]
                                      [#:limit limit (or/c uint32/c #f) #f])
                       Expr-ptr?])]{
  Each null takes the nearest non-null value before it (@tt{.forward_fill})
  or after it (@tt{.backward_fill}); @racket[#:limit] caps how many nulls in
  a row one value fills.

  @examples[#:eval ev
(define gaps (dataframe (list (series (list 1 polars-null polars-null 4) #:name "v"))))
(select gaps
        (alias (forward-fill "v") "forward")
        (alias (forward-fill "v" #:limit 1) "forward_1")
        (alias (backward-fill "v") "backward"))
(eval:error (forward-fill "v" #:limit -1))]}

@deftogether[(@defproc[(sum [v any/c] ...) any/c]
              @defproc[(mean [v any/c] ...+) any/c]
              @defproc[(min [v any/c] ...) any/c]
              @defproc[(max [v any/c] ...) any/c])]{
  These dispatch on their argument. Applied to a single series, they reduce it
  (dispatching on its dtype): @racket[min] and @racket[max] preserve the
  input dtype, as @racket[sum] does above 16 bits, while @racket[mean] of an
  integer, boolean or decimal series is a @racket[float64], so the mean of an
  integer series is a flonum (see @secref["promotion"]); a @racket['float32]
  series' mean is a @racket['float32] value, and a temporal mean is temporal, a date's a
  datetime. Applied to a single expression or a bare column-name
  string, they produce the corresponding aggregation expression — so
  @racket[(sum (col "value"))] reads like Polars' @tt{col("value").sum()} and is
  used inside @racket[agg] (see @secref["ref-fluent"]). Applied to anything else
  they fall back to the usual numeric behaviour, so @racket[(max 1 2 3)] still
  works.

  A series reduces as in Python Polars: to @racket[polars-null] where the
  reduction is undefined, and to zero for the @racket[sum] of no values.
  A string, temporal or categorical series has no @racket[sum], but a
  duration does, and a small integer one sums as @racket['int64], so its
  total does not wrap.

  @examples[#:eval ev
(define s (series '(1 2 3 4) #:name "v"))
(list (sum s) (mean s) (min s) (max s))
(max 1 2 3)
(define nothing (series (list polars-null polars-null) #:name "n"))
(list (sum nothing) (mean nothing) (min nothing) (max nothing))
(define no-rows (series '() #:dtype 'int64))
(list (sum no-rows) (mean no-rows) (min no-rows) (max no-rows))
(sum (series '(#t #f #t)))
(sum (series '(100 100 100) #:dtype 'int8))
(mean (series '("a" "b")))
(mean (series (list (date 2020 1 2) (date 2020 1 1))))
(eval:error (sum (series '("a" "b"))))
(~> (dataframe (list nothing)) (select (sum "n")))]}

@deftogether[(@defproc[(count    [x any/c]) any/c]
              @defproc[(n-unique [x (or/c series? string? Expr-ptr?)]) any/c]
              @defproc[(median   [x any/c]) any/c]
              @defproc[(std [x (or/c series? string? Expr-ptr?)]
                            [#:ddof ddof uint8/c 1]) any/c]
              @defproc[(var [x (or/c series? string? Expr-ptr?)]
                            [#:ddof ddof uint8/c 1]) any/c]
              @defproc[(alias [e (or/c Expr-ptr? string?)] [name string?]) Expr-ptr?])]{
  Aggregation-expression builders for use inside @racket[agg], alongside the
  expression arms of @racket[sum], @racket[mean], @racket[min] and @racket[max].
  Each accepts an expression or a bare column-name string (lifted with
  @racket[col]), so @racket[(count "value")] and @racket[(count (col "value"))]
  are equivalent. @racket[alias] names a result, matching Polars' @tt{.alias}:
  @racket[(alias (sum (col "value")) "total")]. @racket[std] and @racket[var]
  take a @racket[#:ddof] degrees-of-freedom adjustment, defaulting to 1.
  An @racket[alias] name may hold any character, a NUL included, as in Python.
  On a series, @racket[n-unique], @racket[std] and @racket[var] reduce at
  once, as in Python Polars, with every null one unique value. The
  @racket[std] and @racket[var] of fewer than @racket[(+ ddof 1)] values
  are @racket[polars-null], and a string, temporal or categorical series
  has neither, though a duration has a @racket[std].

  @examples[#:eval ev
(list (std nothing) (var nothing) (n-unique nothing))
(list (std (series '(5))) (std (series '(#t #f))) (n-unique (series (list 1 polars-null))))
(eval:error (var (series '("a" "b"))))
(~> (dataframe (list nothing)) (select (count "n")))
(~> (dataframe (list (series '(1) #:name "a")))
    (select (alias (col "a") "a\u0000b"))
    column-names)]}

@deftogether[(@defproc[(first [x (or/c string? pair? any/c)]) any/c]
              @defproc[(last  [x (or/c string? pair? any/c)]) any/c])]{
  Dual-purpose. On an expression or column-name string they build the
  first/last-element aggregation (Polars' @tt{.first()} / @tt{.last()}), for use
  inside @racket[agg]. On a list they are the ordinary list accessors, so
  @racket[(first '(1 2 3))] is @racket[1] and @racket[(last '(1 2 3))] is
  @racket[3] — matching @racketmodname[racket/list].

  @bold{Name clash.} @racketmodname[racket/list] also exports @racket[first] and
  @racket[last] (along with @racket[count] and @racket[group-by], which polars
  exports too). Requiring both modules @emph{explicitly} —
  @racket[(require racket/list polars)] — is an error
  (@tt{identifier already required}). A plain @hash-lang[] @racketmodname[racket/base]
  program is unaffected, because @racketmodname[racket/base] does not export
  these names. See @secref["fluent-shadowing"] for how to take control.}

@deftogether[(@defproc[(pow [x (or/c Expr-ptr? string?)] [exponent (or/c Expr-ptr? real?)]) Expr-ptr?]
              @defproc[(round [x (or/c Expr-ptr? string? number?)]
                              [#:decimals decimals uint32/c 0]) any/c])]{
  Element-wise power (@tt{**}) and rounding to @racket[#:decimals] places
  (@tt{.round}). Each takes an expression or a bare column-name string (lifted
  with @racket[col]); @racket[round] on a plain number falls back to numeric
  rounding, where @racket[decimals] may be any number. Ties round to even in
  both cases, as in Python Polars and @racketmodname[racket/base]. See
  @secref["fluent-shadowing"].

  @examples[#:eval ev
(~> (dataframe (list (series '(-2.5 -1.5 0.5 1.5 2.5) #:name "x")))
    (select (round "x")))
(round 2.5)
(round 1234 #:decimals -2)
(eval:error (round "x" #:decimals -1))]}

@defproc[(sign [x (or/c Expr-ptr? string?)]) Expr-ptr?]{
  The sign of each element (@tt{.sign}): @racket[-1], @racket[0] or
  @racket[1] in the column's own dtype, so a float column gives
  @racket[-1.0], @racket[0.0] and @racket[1.0].

  @examples[#:eval ev
(~> (dataframe (list (series '(-2 0 3) #:name "i") (series '(-2.5 0.0 3.5) #:name "f")))
    (select (sign "i") (sign "f")))]}

@deftogether[(@defproc[(is-between [x (or/c Expr-ptr? string?)] [lower any/c] [upper any/c]
                                   [#:closed closed (or/c 'both 'left 'right 'none) 'both])
                       Expr-ptr?]
              @defproc[(is-in [x (or/c Expr-ptr? string?)] [rhs (or/c list? series? Expr-ptr?)])
                       Expr-ptr?])]{
  Range and membership predicates (@tt{.is_between}, @tt{.is_in}). Bounds are
  lifted with @racket[lit], so gregor dates and datetimes bound a temporal
  column (@secref["ref-temporal-values"]). A list @racket[rhs] holds integers,
  reals, strings, symbols (read as strings, as @racket[lit] reads them),
  booleans or gregor values, all of one kind, among which
  @racket[polars-null] may appear; a list of @racket[polars-null] alone is a
  @racket['null] list, as Python's @tt{[None]} is, and an empty list
  holds nothing, so every non-null element of @racket[x] gives @racket[#f].
  A null is never a member, so a null element of @racket[x] gives null.
  Its integers all fit Int64 or all lie from 0 to @racket[(sub1 (expt 2 64))]
  (UInt64); any other, such as a negative integer beside one past Int64,
  which Python reads as Int128, is a contract error. Integers and floats do not
  mix: a list holding an exact integer and a flonum (or an exact non-integer) is
  a contract error, as Python's @tt{is_in} raises a @tt{TypeError}; write the
  integers as floats (@racket[3.0]). Python reads @tt{[2.5, 1]}, whose first
  element is a float, as floats; either order is refused here. Its datetimes
  share one zone, or none: a list that mixes naive datetimes and moments, or
  moments in two zones, raises, as Python's @tt{is_in} does, although
  @racket[series] builds a column from the same list.

  @examples[#:eval ev
(define gappy (dataframe (list (series (list 1 polars-null 3) #:name "x"))))
(~> gappy (select (is-in "x" (list 1 polars-null))))
(~> gappy (select (is-in "x" (list polars-null))))
(~> gappy (select (is-in "x" '())))
(~> gappy (select (is-in "x" (list (expt 2 63) 3))))
(eval:error (~> gappy (select (is-in "x" (list -1 (expt 2 63))))))
(~> gappy (select (is-in "x" (list 1.0 2.5))))
(eval:error (~> gappy (select (is-in "x" (list 1 2.5)))))
(~> gappy (select (is-between "x" 2 5)))]}

@deftogether[(@defproc[(dt-year   [x (or/c Expr-ptr? string?)]) Expr-ptr?]
              @defproc[(dt-month  [x (or/c Expr-ptr? string?)]) Expr-ptr?]
              @defproc[(dt-day    [x (or/c Expr-ptr? string?)]) Expr-ptr?]
              @defproc[(dt-hour   [x (or/c Expr-ptr? string?)]) Expr-ptr?]
              @defproc[(dt-minute [x (or/c Expr-ptr? string?)]) Expr-ptr?]
              @defproc[(dt-second [x (or/c Expr-ptr? string?)]) Expr-ptr?])]{
  Temporal component accessors on a date or datetime column (@tt{.dt.year()}
  and friends). Also exported, with the same shape: @racketid[dt-iso-year],
  @racketid[dt-quarter], @racketid[dt-week], @racketid[dt-weekday],
  @racketid[dt-ordinal-day], @racketid[dt-is-leap-year], @racketid[dt-date],
  @racketid[dt-time], @racketid[dt-millisecond], @racketid[dt-microsecond],
  @racketid[dt-nanosecond], @racketid[dt-timestamp], @racketid[dt-strftime],
  @racketid[dt-truncate].}

@defproc[(str-slice [x (or/c Expr-ptr? string?)]
                    [offset (or/c Expr-ptr? int64/c)]
                    [length (or/c #f polars-null? Expr-ptr? nonnegative-int64/c) #f])
         Expr-ptr?]{
  Substring of @racket[length] characters from @racket[offset]
  (@tt{.str.slice}); a negative @racket[offset] counts from the end;
  @racket[#f] (or @racket[polars-null], or a null row of a @racket[length]
  expression) runs to the end.

  @examples[#:eval ev
(define words (dataframe (list (series (list "hello" "héllo" polars-null "ab") #:name "s")
                               (series (list 1 polars-null 2 0) #:name "n"))))
(select words
        (alias (str-slice "s" 1 #f) "rest")
        (alias (str-slice "s" -2) "last2")
        (alias (str-slice "s" 0 (col "n")) "by_col"))
(eval:error (str-slice "s" 0 -1))]}

@deftogether[(@defproc[(str-extract [x (or/c Expr-ptr? string?)] [pattern string?]
                                    [#:group-index group-index size/c 1])
                       Expr-ptr?]
              @defproc[(str->date [x (or/c Expr-ptr? string?)]
                                  [#:format format (or/c string? #f) #f]
                                  [#:strict strict boolean? #t]
                                  [#:exact exact boolean? #t]
                                  [#:cache cache boolean? #t])
                       Expr-ptr?]
              @defproc[(str->datetime [x (or/c Expr-ptr? string?)]
                                      [#:format format (or/c string? #f) #f]
                                      [#:unit unit (or/c 'milliseconds 'microseconds 'nanoseconds) 'microseconds]
                                      [#:time-zone time-zone (or/c non-empty-string? #f) #f]
                                      [#:ambiguous ambiguous
                                       (or/c 'raise 'earliest 'latest 'null) 'raise]
                                      [#:strict strict boolean? #t]
                                      [#:exact exact boolean? #t]
                                      [#:cache cache boolean? #t])
                       Expr-ptr?])]{
  @racket[str-extract] returns capture group @racket[#:group-index] of the
  first regex match (@tt{.str.extract}). @racket[str->date] and
  @racket[str->datetime] parse strings with a chrono @tt{strptime}
  @racket[#:format], inferred when omitted (@tt{.str.to_date},
  @tt{.str.to_datetime}); @racket[#:strict #f] yields null instead of raising
  on unparseable values. A UTC offset parsed with @litchar{%z} converts each
  value to UTC, so the column is @racket['(datetime unit "UTC")], as in
  Python; without a @racket[#:format] or a @racket[#:time-zone], an offset
  in the data is an error, as it is on Python's expressions.
  @racket[#:time-zone] parses into that zone: a value with an offset
  converts to it, and one without is read as a wall-clock time there, with
  @racket[#:ambiguous] as @racket[dt-replace-time-zone] takes it (a
  @racket['null] counts as a value that did not parse, so it needs
  @racket[#:strict #f]). A wall-clock time the zone skips raises when the
  plan runs; Python's @tt{to_datetime} has no @tt{non_existent} either, so
  parse without @racket[#:time-zone] and give the column to
  @racket[dt-replace-time-zone] with @racket[#:non-existent] @racket['null]
  to read it as null.

  @examples[#:eval ev
(define stamps
  (dataframe (list (series '("2021-03-27T00:00:00+0100" "2021-03-29T00:00:00+0200")
                           #:name "at")
                   (series '("2021-03-27 03:00" "2021-10-31 02:30") #:name "clock"))))
(select stamps (str->datetime "at" #:format "%Y-%m-%dT%H:%M:%S%z"))
(select stamps
        (str->datetime "at" #:time-zone "Asia/Tokyo")
        (str->datetime "clock" #:time-zone "Europe/Brussels" #:ambiguous 'latest))
(select (dataframe (list (series '("2021-03-28 01:30" "2021-03-28 02:30") #:name "clock")))
        (~> (str->datetime "clock")
            (dt-replace-time-zone "Europe/Brussels" #:non-existent 'null)))
(eval:error (str->datetime "at" #:time-zone "Asia/Tokio"))]}

@deftogether[(@defproc[(dt-convert-time-zone [x (or/c series? Expr-ptr? string?)]
                                             [zone non-empty-string?])
                       (or/c series? Expr-ptr?)]
              @defproc[(dt-replace-time-zone [x (or/c series? Expr-ptr? string?)]
                                             [zone (or/c non-empty-string? #f)]
                                             [#:ambiguous ambiguous
                                              (or/c 'raise 'earliest 'latest 'null) 'raise]
                                             [#:non-existent non-existent (or/c 'raise 'null)
                                              'raise])
                       (or/c series? Expr-ptr?)])]{
  Move a datetime series, or the datetime column an expression or a column
  name gives, between zones (@tt{.dt.convert_time_zone},
  @tt{.dt.replace_time_zone}). @racket[dt-convert-time-zone] keeps each
  instant and changes the clock it reads in; a naive datetime is read as
  UTC. @racket[dt-replace-time-zone] keeps each wall-clock time and changes
  the instant: @racket[zone] @racket[#f] makes the column naive, and a zone
  sets one on a naive column or replaces a column's zone. Polars computes
  that wall clock without an overflow check, so on a nanosecond column a
  value within a day of either end of the range (1677-09-21, 2262-04-11)
  wraps around, as it does in Python; reading the zoned value itself, with
  @racket[ref] or a conversion, does not.

  A wall-clock time can name two instants, when the clocks go back, or
  none, when they go forward. @racket[#:ambiguous] picks the
  @racket['earliest] or @racket['latest] of two, or @racket['null];
  @racket[#:non-existent] @racket['null] gives null for a time that does not
  exist. Both default to @racket['raise], as Python's do. Zones are named as
  the tz database names them; a zone polars does not know raises, with the
  nearest name it does. On an expression, an ambiguous or non-existent time
  is reported when the plan runs. API gap: Python's @tt{ambiguous} may also
  be an expression, resolving each row its own way; here it is one symbol
  for the whole column (#171).

  @examples[#:eval ev
(define clocks
  (dataframe (list (series (list (datetime 2021 3 27 3) (datetime 2021 10 31 2 30))
                           #:name "clock"))))
(select clocks
        (~> "clock" (dt-replace-time-zone "UTC") (alias "utc"))
        (~> "clock" (dt-replace-time-zone "UTC") (dt-convert-time-zone "Asia/Kathmandu")
            (alias "kathmandu"))
        (~> "clock" (dt-replace-time-zone "Europe/Brussels" #:ambiguous 'earliest)
            (alias "brussels")))
(dt-replace-time-zone (ref clocks "clock") "Europe/Brussels" #:ambiguous 'latest)
(eval:error (dt-replace-time-zone (ref clocks "clock") "Europe/Brussels"))
(define skipped (series (list (datetime 2021 3 28 1 30) (datetime 2021 3 28 2 30))
                        #:name "clock"))
(dt-replace-time-zone skipped "Europe/Brussels" #:non-existent 'null)
(eval:error (dt-replace-time-zone skipped "Europe/Brussels"))
(eval:error (dt-convert-time-zone "clock" "Asia/Kathmando"))]}

@subsection[#:tag "fluent-shadowing"]{Shadowed bindings}

@racket[(require polars)] re-exports a handful of generic operations whose names
also live in @racketmodname[racket/base] (@racket[min], @racket[max],
@racket[sort], @racket[filter], @racket[>], @racket[<], @racket[>=],
@racket[<=], @racket[=]) and in @racketmodname[racket/list] (@racket[first],
@racket[last], @racket[count], @racket[group-by]). Under
@hash-lang[] @racketmodname[racket/base] this is seamless — these names are
either not bound (so polars simply provides them) or bound only by the module
@emph{language} (which an explicit @racket[require] silently shadows), and the
polars versions intentionally fall back to the numeric/list behaviour for
non-frame arguments.

A conflict arises only when another module providing the same name is
@emph{also} required explicitly — most commonly @racketmodname[racket/list].
Resolve it with the usual @racket[require] sub-forms:

@racketblock[
(code:comment "keep polars' first/last/count/group-by, drop racket/list's:")
(require (except-in racket/list first last count group-by) polars)

(code:comment "keep racket/list's, reach polars' under a prefix:")
(require racket/list (prefix-in pl: polars))
(code:comment "then (pl:first (col \"v\")) for the Expr, (first '(1 2 3)) for the list")

(code:comment "keep polars', reach racket/list's under a prefix:")
(require polars (prefix-in list: racket/list))
]

@section[#:tag "ref-series"]{Series}

A @tech{series} wraps a typed column and prints in the REPL the way Polars
prints it; @racket[series?] is its predicate. (The underlying foreign pointer is
an implementation detail and not part of the public series API.)

@defproc[(series? [v any/c]) boolean?]{
  Returns @racket[#t] if @racket[v] is a series.}

@defproc[(series [elements (or/c list? vector?)]
                 [#:name name utf-8-name/c ""]
                 [#:dtype dtype (or/c #f symbol? pair?) #f])
         series?]{
  Builds a series from a list or vector. When @racket[#:dtype] is omitted the
  dtype is inferred from the elements: an empty list or vector, or one
  holding @racket[polars-null] alone, is a @racket['null] series, as
  Python's @tt{pl.Series([])} and @tt{pl.Series([None])} are, and a null
  among other values takes their dtype. Otherwise it is
  taken from @racket[dtype], and @racket['null] takes only
  @racket[polars-null] elements. Both short spellings (@racket['i32], @racket['f64],
  @racket['str], @racket['bool]) and canonical symbols (@racket['int32],
  @racket['float64], @racket['string], @racket['boolean]) are accepted. Use
  @racket[polars-null] for missing values. Exact integers are coerced to
  flonums when the target dtype is floating point. Symbols infer
  @racket['categorical]; a @racket['categorical] or Enum (@racket[define-enum])
  series is built from strings or symbols alike, and an Enum raises on a
  value outside its categories (@secref["ref-categorical"]). gregor dates,
  times, datetimes, moments and periods infer the temporal dtypes; a
  datetime or duration column is microseconds, or nanoseconds when a value
  carries a sub-microsecond part and a nanosecond column holds every value,
  and moments make a zoned datetime column (@secref["ref-temporal-values"]).
  A name may hold any character, a NUL included, as in Python, and may be a
  byte string or path whose bytes are UTF-8, as every @racket[utf-8-name/c] may.

  @examples[#:eval ev
(series '(1 2 3) #:name "ints")
(column-names (dataframe (list (series '(1) #:name "a") (series '(2) #:name "a\u0000b"))))
(eval:error (series '(1) #:name 'ints))
(series '())
(series (list polars-null polars-null))
(series '() #:name "empty" #:dtype 'f64)
(eval:error (series '(1 2) #:dtype 'null))
(series '(1.5 2.5) #:name "floats" #:dtype 'f32)
(series (list 1 polars-null 3) #:name "with-null")
(series '(IAH ATL IAH) #:name "dest")
(series (list (date 1997 1 10) (date 1985 2 15)) #:name "birthdate")
(define-enum severity debug info error)
(series '("debug" "error") #:dtype severity)
(eval:error (series '(debug fatal) #:dtype severity))]}

@defproc[(series->string [s series?]) string?]{
  Renders @racket[s] in Polars' series format (a @tt{shape} line, a
  @tt{Series: 'name' [dtype]} line, then the bracketed values, truncated to the
  first and last five when longer than ten). This is also what a series prints
  as in the REPL. A @racket['binary] value shows bytes @tt{!} to @tt{~} as
  themselves and any other as @tt{\xNN}, cut after 60 bytes, as in Python.
  A value that cannot be shown prints as @tt{#<cannot print: reason>}, and a
  series that cannot be shown at all as @tt{#<series: cannot print:
  reason>}, where @racket[series->string] raises.

  @examples[#:eval ev #:label #f
(~> (series '("a" "z q" "") #:name "blob") (cast 'binary))]}

@deftogether[(@defthing[polars-null any/c]
              @defproc[(polars-null? [v any/c]) boolean?])]{
  @racket[polars-null] is the sentinel marking a missing value: pass it among the
  elements given to @racket[series] to produce nulls, and it is what @racket[ref]
  returns for a null entry, and what the conversions in
  @secref["ref-series-convert"] return by default. @racket[polars-null?] tests
  for it.}

@deftogether[(@defproc[(dtype [s has-dtype?]) (or/c symbol? pair?)]
              @defproc[(len [x sized?]) exact-nonnegative-integer?]
              @defproc[(null-count [s has-null-count?]) exact-nonnegative-integer?])]{
  Generic series accessors. @racket[dtype] returns the canonical dtype symbol
  (e.g. @racket['int32], @racket['float64], @racket['categorical]) or list
  (@racket['(datetime milliseconds #f)],
  @racket['(datetime microseconds "Europe/Brussels")],
  @racket['(enum low mid high)], @racket['(decimal 10 2)]).
  @racket[len] returns the number of elements (and, on a dataframe, the number of
  rows). @racket[null-count] returns the number of null entries.}

@defproc[(series-name [s series?]) string?]{
  Returns the name of @racket[s], as Polars' @tt{Series.name}; a column taken
  from a dataframe is named after the column.

  @examples[#:eval ev #:label #f
(series-name (series '(1 2) #:name "ints"))]}

@deftogether[(@defproc[(rename [s series?] [new-name utf-8-name/c]) series?]
              @defproc[#:link-target? #f
                       (rename [d dataframe?] [old utf-8-name/c] [new utf-8-name/c])
                       dataframe?]
              @defproc[(rename! [s series?] [new-name utf-8-name/c]) void?]
              @defproc[(clone [s series?]) series?]
              @defproc[(series-clone [s series?]) series?])]{
  @racket[rename!] renames a series in place (matching Polars), returning
  @racket[void] as is conventional for @litchar{!} mutators; @racket[rename]
  returns a renamed copy and leaves the original untouched. On a dataframe,
  @racket[rename] returns a copy whose column @racket[old] is named
  @racket[new] (@tt{df.rename}); @racket[old] must be a column, and
  @racket[new] must not name another. @racket[clone] (and its series-specific
  alias @racket[series-clone]) returns an independent copy.

  @examples[#:eval ev
(series-name (rename (series '(1) #:name "a") "b"))
(define named (dataframe (list (series '(1) #:name "a") (series '(2) #:name "b"))))
(rename named "a" "z")
(eval:error (rename named "a" "b"))]}

@subsection[#:tag "ref-series-convert"]{Converting to Racket values}

These copy a column out of Polars in one foreign call rather than one per
element: Racket allocates a buffer of the column's native type, Rust copies
the values into it, and Racket builds its values from the buffer and frees it.
Nothing crosses the boundary to be freed later. At its peak a conversion holds
that buffer (one native value per row, plus a byte per row when the column has
nulls) beside the result it builds; @racket[in-series] instead converts
@racket[4096] rows at a time. Each element comes out as @racket[ref] returns
it:

@tabular[#:style 'boxed #:sep @hspace[2]
 (list (list @bold{dtype} @bold{element})
       (list "integer dtypes" @racket[exact-integer?])
       (list @elem{@racket['float32], @racket['float64]} @racket[flonum?])
       (list @racket['boolean] @racket[boolean?])
       (list @racket['string] @racket[string?])
       (list @elem{@racket['categorical], @racket['(enum cat ...)]} @racket[symbol?])
       (list @racket['(decimal precision scale)] @elem{an exact rational, as @racket[exact?]})
       (list @racket['date] @elem{a gregor @tt{date}})
       (list @racket['(datetime unit tz)] @elem{a gregor @tt{datetime}, to the column's unit})
       (list @racket['(duration unit)] @elem{a gregor @tt{period} in that unit})
       (list @racket['time] @elem{a gregor @tt{time}})
       (list @racket['null] "the null value"))]

A null entry becomes the @racket[#:null] value. A series of any other dtype
raises @racket[exn:fail:contract] naming the dtype, even when every entry is
null. The @secref["interop"]
chapter of the guide walks through all of them.

@examples[#:eval ev #:hidden (require ffi/vector)]

@examples[#:eval ev #:label #f
(series->list (series (list 1.5 polars-null)))
(series->list (series (list "a" polars-null "")))
(series->list (series (list #t #f polars-null)))
(series->list (series (list (datetime 2024 1 2 3 4 5 678000000) polars-null)))
(series->list (cast (series '(19724) #:dtype 'i32) 'date))
(series->list (cast (series '(11045000000000) #:dtype 'i64) 'time))
(series->list (cast (series '(1500) #:dtype 'i64) '(duration milliseconds)))
(series->list (cast (series (list "UA" polars-null "UA")) 'categorical))
(series->list (ref (read-parquet "produce.parquet") "price"))
(eval:error (series->list (cast (series '("a") #:name "b") 'binary)))]

@deftogether[(@defproc[(series->list [s series?] [#:null null-value any/c polars-null]) list?]
              @defproc[(series->vector [s series?] [#:null null-value any/c polars-null])
                       vector?])]{
  Returns the elements of @racket[s] in order, as a fresh list or a fresh
  mutable vector, with @racket[null-value] in place of each null entry. Mirrors
  Polars' @tt{Series.to_list()}, with @racket[polars-null] for @tt{None}.

  @examples[#:eval ev #:label #f
(define s (series (list 3 polars-null 1) #:name "x"))
(series->list s)
(series->list s #:null 'missing)
(series->vector s)
(series->vector s #:null 0)]}

@defproc[(series->f64vector [s series?] [#:null null-value (or/c real? 'error) +nan.0])
         f64vector?]{
  Copies a numeric series into a fresh @racket[f64vector], the
  @racketmodname[ffi/vector] type that foreign code takes. Integers become the
  nearest flonum, as @racket[exact->inexact] gives, and booleans become
  @racket[1.0] and @racket[0.0]. A null entry becomes @racket[null-value] as a
  flonum, as @tt{Series.to_numpy()} gives @tt{nan}; with @racket['error] a null
  raises @racket[exn:fail:contract] naming its row. Any other dtype raises
  @racket[exn:fail:contract] naming the dtype.

  The result is ordinary garbage-collected memory, which Racket CS may move:
  pass it to a foreign call that is not @racket[#:blocking?], and do not let
  foreign code keep the pointer past the call.

  @examples[#:eval ev #:label #f
(define xs (series (list 1 polars-null 3) #:name "x"))
(f64vector->list (series->f64vector xs))
(f64vector->list (series->f64vector xs #:null 0))
(f64vector->list (series->f64vector (series (list #t #f))))
(f64vector->list (series->f64vector (series '(1 2)) #:null 'error))
(eval:error (series->f64vector xs #:null 'error))
(eval:error (series->f64vector (series '("a") #:name "s")))]}

@defproc[(in-series [s series?] [#:null null-value any/c polars-null]) sequence?]{
  Returns a sequence of the elements of @racket[s], converted as by
  @racket[series->list] but 4096 rows at a time, so it never holds more than
  one block's buffer and a loop that stops early converts little more than it
  reads. A series is itself a sequence:
  @racket[(for ([x s]) ....)] iterates as @racket[(in-series s)] does.

  @examples[#:eval ev #:label #f
(for/list ([x (in-series xs)]) x)
(for/sum ([x (in-series xs #:null 0)]) x)
(for/list ([x (series '("a" "b"))]) (string-upcase x))
(for/first ([x (in-series (series (build-list 100000 values)))]
            #:when (> x 41))
  x)]}

@subsection[#:tag "ref-temporal-values"]{Dates, times, datetimes and durations}

The temporal dtypes cross the boundary as gregor values, both ways: a
@racket['date] column holds gregor @tt{date}s, a @racket['time] column gregor
@tt{time}s, a @racket['(datetime unit #f)] column gregor @tt{datetime}s, a
zoned @racket['(datetime unit "Zone/Name")] column gregor @tt{moment}s in its
zone and a @racket['(duration unit)] column gregor @tt{period}s.
@racket[series] infers the dtype from the values, as Python's
@tt{pl.Series} does from @tt{date}, @tt{time}, @tt{datetime} and
@tt{timedelta}, and @racket[lit] makes the literal of the same dtype:

@tabular[#:style 'boxed #:sep @hspace[2]
 (list (list @bold{gregor value} @bold{inferred dtype})
       (list @tt{date} @racket['date])
       (list @tt{time} @racket['time])
       (list @tt{datetime} @elem{@racket['(datetime microseconds #f)], or
                                 @racket['(datetime nanoseconds #f)]})
       (list @tt{moment} @elem{@racket['(datetime microseconds "Zone/Name")],
                               or nanoseconds})
       (list @elem{@tt{period} without years or months}
             @elem{@racket['(duration microseconds)], or
                   @racket['(duration nanoseconds)]}))]

Python's @tt{datetime} and @tt{timedelta} stop at the microsecond, so
Python's unit is always microseconds; gregor's go to the nanosecond. A column
(or a literal) is nanoseconds, so nothing is lost, when a value has a nonzero
sub-microsecond part and a nanosecond column holds every value: datetimes
from 1677-09-21 00:12:43.145224192 to 2262-04-11 23:47:16.854775807,
durations shorter than 2@superscript{63} nanoseconds (about 292 years) either
way. Otherwise it is microseconds, which hold every datetime Polars can
print, and the sub-microsecond part is dropped as @racket[#:dtype] drops it
(below). gregor's @tt{now} reads a flonum clock and nearly always has a
sub-microsecond part: a column of @tt{now}s alone is then nanoseconds, and
one that also holds a datetime from 1600 is microseconds.

A period's weeks, days, hours and smaller fields add up to one fixed length
(a day is 24 hours, as in Polars); years and months have no fixed length and
are refused. With @racket[#:dtype], a value is converted to the dtype's unit
and a finer part dropped as Polars' own casts drop it: a datetime is floored,
a duration truncated toward zero. A value the dtype cannot hold raises, and
so does a date or datetime outside the years -262143 to 262142, which Polars
cannot print.

A gregor @tt{moment} is an instant with a time zone, and makes a zoned
column, as Python's aware @tt{datetime} does. A column has one zone, so a
list settles it as Python settles a list: the first value that is not null
decides. A moment in a named zone gives that zone, @racket["Europe/Brussels"]
or @racket["UTC"]; a moment at a fixed offset (gregor's @racket[#:tz 3600])
gives @racket["UTC"]; and each other moment keeps its instant in that zone.
A naive gregor @tt{datetime} in a zoned column is read as UTC, and a list
whose first value is naive makes a naive column of each moment's UTC clock
time. @racket[#:dtype] names the column's dtype outright, under the same
reading: a zoned dtype converts every moment to its zone, and a naive one
takes each moment's UTC clock time, where Python's
@tt{pl.Datetime("us")} keeps the values' zone.

Polars reads zones from chrono-tz's compiled copy of the tz database, and
every reading here is Polars': a moment read back carries the offset Polars
gives its instant, and a printed series or dataframe and @racket[describe]
show what Python shows. gregor's own functions --- @tt{moment}, and its
arithmetic on a moment --- read zones through tzinfo instead, from the
system's zoneinfo (or the tzdata package's copy, when it is installed), and
the two can disagree. tzinfo ignores the rule a zoneinfo file gives for
times after its last listed change, so it misses daylight saving after 2037,
and on a system whose zoneinfo is built "slim", sooner; many systems merge
zones' histories before 1970; and some lack the old names, such as
@racket["US/Pacific"], that a column may still carry (#172). The instant is never
in doubt: a moment you build stores the instant its own offset gives, and a
moment read back is the column's instant.

Reading back, @racket[ref] and every conversion in
@secref["ref-series-convert"] return each value with its column's full
precision: a millisecond, microsecond or nanosecond datetime as the gregor
@tt{datetime} (or, for a zoned column, @tt{moment} in the column's zone) of
exactly that instant, where Python's @tt{to_list} stops at the
microsecond. A date column's years may be negative, as gregor's and
Polars' may.

@examples[#:eval ev #:hidden (require gregor/period gregor/time)]

@examples[#:eval ev #:label #f
(series (list (date 2013 1 1) polars-null (date -1300 5 23)) #:name "d")
(series (list (time 5 6 7 123456789)) #:name "t")
(series (list (datetime 2013 1 1 5 6 7 123456000)) #:name "dt")
(series (list (datetime 2013 1 1 5 6 7 123456789)) #:name "dt")
(series (list (datetime 2013 1 1 5 6 7 123456789) (datetime 1600 1 1)) #:name "dt")
(series (list (hours 36) (minutes 90)) #:name "wait")
(series (list (datetime 2013 1 1 5 6 7 123456789))
        #:name "dt" #:dtype '(datetime milliseconds))
(series->list (cast (series '(1500 -1) #:dtype 'i64) '(datetime milliseconds)))
(define calendar
  (dataframe (list (series (list (date 2013 5 31) (date 2013 6 1) (date 2013 6 2))
                           #:name "d")
                   (series '(1 2 3) #:name "v"))))
(filter calendar (> (col "d") (date 2013 6 1)))
(filter calendar (is-between "d" (date 2013 5 31) (datetime 2013 6 1 12)))
(filter calendar (is-in "d" (list (date 2013 5 31) (date 2013 6 2))))
(eval:error (is-in "d" (list (datetime 2013 5 31) (moment 2013 6 2 #:tz "UTC"))))
(series (list (moment 2021 3 27 #:tz "Europe/Brussels")
              (moment 2021 3 28 5 #:tz "Europe/Brussels")
              (moment 2021 3 27 #:tz "Asia/Kathmandu"))
        #:name "zoned")
(series->list (series (list (moment 2021 3 27 #:tz 3600)) #:name "offset"))
(series (list (datetime 2021 3 27 12)) #:dtype '(datetime milliseconds "Europe/Brussels"))
(eval:error (series (list (datetime 2021 3 27)) #:dtype '(datetime microseconds "Mars/Base")))
(eval:error (series (list (months 1))))
(eval:error (series (list (datetime 1500 1 1)) #:dtype '(datetime nanoseconds)))]

@subsection[#:tag "ref-categorical"]{Categorical, Enum and Decimal}

A @racket['categorical] column stores each distinct string once and a code
per row, as Polars' @tt{Categorical}; an Enum column (dtype
@racket['(enum cat ...)], defined with @racket[define-enum]) does the same
over categories declared up front, in order, as @tt{pl.Enum}. Both read back as symbols, which Racket interns: a symbol is
already the dictionary encoding. The codes stay inside Polars. Every
categorical column in the process shares them, and they restart once the
last one is dropped, so each conversion fetches the strings afresh.

@itemlist[
  @item{Build one with @racket[series] (a list of symbols infers
    @racket['categorical]), @racket[cast], or
    @racket[read-csv]'s @racket[#:schema-overrides] (@racket['categorical]
    only).}
  @item{A categorical sorts and compares by its strings; an Enum by the
    declared order of its categories.}
  @item{A value outside an Enum's categories raises, whether it is built,
    cast or compared; a categorical takes any string.}
  @item{API gap: a categorical or Enum value that @racket[series] builds,
    and an Enum category, cannot hold a NUL character (@racket[#\nul]): it
    raises. A @racket['string] value can hold one.}
  @item{Two categorical columns share one encoding, so they join, stack
    and compare without re-encoding; two Enums with the same categories
    are the same dtype.}
  @item{@racket[describe] gives a categorical or Enum column
    @tt{count} and @tt{null_count} only, as Python does.}]

@defform[(define-enum id category ...+)
         #:grammar ([category id string])]{
  Binds @racket[id] to the Enum dtype with the given categories, in order:
  the datum @racket['(enum category ...)] that @racket[dtype] reports for
  such a column, so @racket[equal?] compares the two. A string category is
  the symbol of that string, for a name that is not an identifier. A
  duplicate category, one holding a NUL character, or none, is a syntax
  error. The datum itself is
  accepted wherever a dtype is (@tt{pl.Enum([...])}).

  @examples[#:eval ev #:label #f
  (define-enum log-levels debug info warning error)
  log-levels
  (define levels (series '(debug info debug error) #:name "level" #:dtype log-levels))
  (equal? (dtype levels) log-levels)
  (series->list (cast (series '("warning" "info")) log-levels))
  (define-enum sizes small "Very High")
  sizes
  (eval:error (define-enum twice debug info debug))
  (eval:error (series '(info fatal) #:dtype log-levels))]}

A @racket['(decimal precision scale)] column holds exact decimals, which
@racket[ref] and the conversions read as exact rationals. Decimal columns
come from Parquet; @racket[cast] reads them into other dtypes. API gap: no
@racket[#:dtype] or @racket[cast] to a Decimal.

@examples[#:eval ev #:label #f
(define logs
  (dataframe
   (list (series '(debug info debug error) #:name "level" #:dtype log-levels)
         (series '(api db api db) #:name "source"))))
(for/list ([name (column-names logs)]) (dtype (ref logs name)))
(filter logs (> (col "level") 'info))
(sort logs "level")
(sort logs "source")
(ref (ref logs "source") 1)
(select logs (col 'categorical))
(eval:error (select logs (> (col "level") 'fatal)))
(eval:error (series (list "api" "d\u0000b") #:dtype 'categorical))
(define produce (read-parquet "produce.parquet"))
(dtype (ref produce "price"))
(for/sum ([price (ref produce "price")] #:unless (polars-null? price)) price)]

@subsection[#:tag "promotion"]{dtype promotion}

Reductions follow a simple, predictable rule. The widening order, narrow to
wide, is

@itemlist[
  @item{@racket['int8] < @racket['int16] < @racket['int32] < @racket['int64]}
  @item{@racket['uint8] < @racket['uint16] < @racket['uint32] < @racket['uint64]}
  @item{any integer < @racket['float32] < @racket['float64]}
]

@racket[sum], @racket[min] and @racket[max] preserve the input dtype.
@racket[mean] promotes to @racket['float64]. Use @racket[series-cast] to change
a series' dtype explicitly.

A plain value beside a series in an operator follows Python 1.42.1's eager
operators. It is a constant of the series' dtype when it fits: a boolean
beside a numeric series is 1 or 0, and a number or boolean compared with a
string series is its string as Python's @tt{str} spells it (@tt{1e-05},
@tt{inf}, @tt{True}). A gregor value keeps its own dtype (but @racket[mod] of
a float series and a datetime reads the datetime's physical integer, as
Python does), a non-integer real beside an integer series is
@racket['float64], and in arithmetic a string or symbol is a string, so
@racket[+] concatenates. Otherwise the operator runs its expression form,
@racket[(_op (col _name) _value)], with that form's dtypes and values: beside
a @racket['null] series (where Python's eager operators raise) or with
@racket[polars-null], beside an Enum series a string or symbol, beside a
Decimal series a real or boolean (compared as 1 or 0), beside a duration
series a number in @racket[*], a string before a series in @racket[+], beside
an integer series an integer within Int64 past the dtype's range (unless a
row's exact result falls outside the dtype that form gives, which raises
@racket[exn:fail:contract] naming the value, as Python's eager operator raises
an @tt{OverflowError} for any such integer), in
@racket[/] a negative integer beside an unsigned series, and beside a
@racket['boolean] series an integer in @racket[/]. An integer from
@racket[(expt 2 63)] to @racket[(sub1 (expt 2 64))], which only @racket[lit]'s
UInt64 literal carries, is a constant beside a @racket['uint64] series (where
Python's operator wraps, as ours does), takes the expression form beside a
Decimal series, and is refused beside any other integer or @racket['boolean]
series and a @racket['null] one, where Python's eager operators raise an
@tt{OverflowError} (a @tt{TypeError} beside Null), except in @racket[/],
where Python gives @racket['float64] (@racket['float64] nulls beside Null)
and ours refuses, since its @racket[/] of integers is integer division;
beside a float or string series it is what any integer is there. Any other
value raises @racket[exn:fail:contract] naming it and the series' dtype,
where Python raises a @tt{TypeError}: a string, symbol or boolean compared with a numeric
series, a gregor value compared with a series of another kind (a date with a
datetime series aside), a time in arithmetic, a date in @racket[mod] of a
float series, a negative integer beside an unsigned series, or a value no
literal takes. @racket[mod] refuses a temporal series, the left one when both
are series, whatever the other operand, as Python's @tt{%} does. A
@racket[/] of integer, boolean or null operands is integer division (the
floored @racket['float64] quotient for a signed integer series beside a
UInt64 one; two
Null operands aside, which give @racket['float64]); any other is Python's
true division, which first casts an integer, boolean or null series, a
Decimal series under a boolean or a temporal value on its left, and a series
under a plain number on its left, to @racket['float64], and divides a duration
series by a number. The result takes the series' name on either side;
Python's eager operator instead names it @tt{literal} for a plain value left
of @racket[+], @racket[-], @racket[*] or @racket[/] on a Decimal series, left
of @racket[*] on a Duration series, and for a string left of @racket[+]. The operand audit (@filepath{polars/tests/generic/operand-audit.rkt}) holds every
operator to Python's outcome, row by row, and records ours, with its reason,
where they still differ.

@examples[#:eval ev #:label #f
(+ (series '(1 2) #:dtype 'u8) 300)
(eval:error (+ (series '(10 20) #:dtype 'i8) (sub1 (expt 2 63))))
(eval:error (- (series '(1 2) #:dtype 'u8) 300))
(+ (series '(1 2) #:dtype 'u64) (expt 2 63))
(eval:error (+ (series '(1 2)) (expt 2 63)))
(+ (series '(1 2)) "x")
(+ (series '(1 2)) #t)
(- 10 (series '(1 2) #:name "n"))
(= (series '("x" "y")) 1)
(= (series '("1e-05" "x")) 1e-5)
(/ (series '(1 2)) (series '(1.5 2.0) #:dtype 'f32))
(mod (series '(1 2)) (series (list (date 2024 1 1) (date 2024 1 2))))
(* (series (list (hours 1) (hours 2))) 2)
(/ (series (list (hours 1) (hours 2))) 2.5)
(= (series (list "low" "mid" polars-null "high") #:dtype '(enum low mid high)) "bogus")
(eval:error (+ (series '(1 2) #:dtype 'u8) -1))
(eval:error (= (series '(1 2)) (date 2024 1 1)))
(eval:error (mod (series (list (date 2024 1 1))) (series '(1))))]

@subsection[#:tag "ref-series-lowlevel"]{Low-level Series API}

The generic layer is built on monomorphic, dtype-suffixed bindings that operate
directly on the foreign series. They remain exported. A @racket[series] wrapper
is accepted anywhere one of them expects a series (the wrapper marshals
transparently, and satisfies @racket[Series-ptr?]), but what they @emph{return}
is the raw foreign pointer, not a wrapper — so the results do not print in
Polars' format and do not answer to @racket[series?]. Prefer @racket[series]
and the generic operations above; reach for these when you need a specific
dtype or a specific typed result.

@defproc[(Series-ptr? [v any/c]) boolean?]{
  Recognises a foreign series pointer. Both raw pointers returned by the
  low-level constructors and @racket[series] wrappers satisfy it.}

@defproc[(series-drop [s Series-ptr?]) void?]{
  Releases the native series @racket[s] holds now, instead of when the
  collector finds @racket[s] unreachable. @racket[s] is a @racket[series]
  wrapper or a raw pointer, and the drop reaches every wrapper of the same
  pointer. A dropped series still answers to @racket[series?] and
  @racket[Series-ptr?], as a closed port is still a port, and prints as
  @racketresultfont{#<series: dropped>}; any later use raises
  @racket[exn:fail:contract]. Dropping it again names @racket[series-drop];
  any other use names the series, as
  @racketerror{series: series has been dropped}, since the check is made where
  the pointer crosses into Polars, not by each verb.

  A drop must not run while another thread uses the same series: the check
  is made as the call converts its arguments, so a drop between that and the
  native call frees memory the call goes on to read, which can crash Racket
  or return wrong values. Nothing guards against it; a program that shares a
  value between threads synchronises the drop with them, or leaves the
  release to the collector, which never runs it while a thread can still
  reach the value.

  @examples[#:eval ev
(define temps (series '(21.5 23.0 19.8) #:name "temp"))
(series-drop temps)
temps
(eval:error (len temps))
(eval:error (series-drop temps))]}

@deftogether[(@defproc[(series-new-i8   [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-i16  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-i32  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-i64  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-u8   [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-u16  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-u32  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-u64  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-f32  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-f64  [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-bool [name utf-8-name/c] [values list?]) Series-ptr?]
              @defproc[(series-new-str  [name utf-8-name/c] [values list?]) Series-ptr?])]{
  Build a series of the dtype named by the suffix from a list of values.
  @racket[polars-null] among the values produces a null entry. Unlike
  @racket[series], no coercion happens: the integer constructors want exact
  integers, the float constructors want flonums (an exact @racket[1] is
  rejected), @racket[series-new-bool] wants booleans and @racket[series-new-str]
  wants strings. Each constructor has a @tt{/vec} sibling
  (@racketid[series-new-i32/vec], @racketid[series-new-f64/vec], …) that takes a
  vector instead of a list.}

@defproc[(series-new-null [name utf-8-name/c] [length size/c]) Series-ptr?]{
  Builds a series of @racket[length] nulls of dtype @racket['null]. It is
  what @racket[(series '())] and @racket[series] with @racket[#:dtype 'null]
  build on.

  @examples[#:eval ev #:label #f
    (display (series->string (series-new-null "nothing" 3)))]}

@deftogether[(@defproc[(series-sum-i32  [s Series-ptr?]) (or/c exact-integer? #f)]
              @defproc[(series-min-i32  [s Series-ptr?]) (or/c exact-integer? #f)]
              @defproc[(series-max-i32  [s Series-ptr?]) (or/c exact-integer? #f)]
              @defproc[(series-mean-i32 [s Series-ptr?]) (or/c flonum? #f)]
              @defproc[(series-sum-f64  [s Series-ptr?]) (or/c flonum? #f)]
              @defproc[(series-min-f64  [s Series-ptr?]) (or/c flonum? #f)]
              @defproc[(series-max-f64  [s Series-ptr?]) (or/c flonum? #f)]
              @defproc[(series-mean-f64 [s Series-ptr?]) (or/c flonum? #f)])]{
  Typed reductions. The suffix names the dtype the series must have
  (@racket['int32] or @racket['float64]); applied to a series of any other
  dtype they return @racket[#f] rather than converting, so
  @racket[(series-sum-i32 (series '(1 2)))] is @racket[#f] because
  @racket[series] infers @racket['int64] for those elements. They also return
  @racket[#f] when the reduction is undefined — the min, max or mean of a
  series whose entries are all null — while the sum of such a series is
  @racket[0]. The generic @racket[sum], @racket[min], @racket[max] and
  @racket[mean] dispatch on the dtype for you, return @racket[polars-null]
  where these return @racket[#f] for an undefined reduction, and are the
  preferred surface.

  @examples[#:eval ev
(define gaps (series (list polars-null polars-null) #:dtype 'float64))
(list (series-min-f64 gaps) (series-sum-f64 gaps) (min gaps))]}

@defproc[(series-cast [s Series-ptr?] [dtype (or/c symbol? pair?)]) Series-ptr?]{
  Returns a copy of @racket[s] converted to @racket[dtype], given as a canonical
  dtype symbol (@racket['int8] through @racket['int64], @racket['uint8] through
  @racket['uint64], @racket['float32], @racket['float64], @racket['boolean],
  @racket['string], @racket['binary], @racket['date], @racket['time],
  @racket['datetime], @racket['duration], @racket['null],
  @racket['categorical]) or the short spelling of one (@racket['i8] through
  @racket['u64], @racket['f32], @racket['f64], @racket['bool],
  @racket['str]), as @racket['(enum cat ...)] with distinct symbols
  for the categories, or, for the two
  temporal dtypes with a time unit, as a list —
  @racket['(datetime milliseconds)], @racket['(duration nanoseconds)] — where
  the unit is one of @racket['nanoseconds], @racket['microseconds] or
  @racket['milliseconds]. Bare @racket['datetime] and @racket['duration]
  default to microseconds. A zoned datetime is
  @racket['(datetime unit "Zone/Name")], with an explicit unit. Raises an
  error when Polars cannot perform the cast. The fluent @racket[cast] wraps
  this for the generic layer.}

@defproc[(series-sort [s Series-ptr?]
                      [#:descending descending boolean? #f]
                      [#:nulls-last nulls-last boolean? #f])
         Series-ptr?]{
  Returns a sorted copy of @racket[s]; the fluent @racket[sort] on a series
  wraps it.}

@section[#:tag "ref-dataframes"]{DataFrames}

A @tech{dataframe} is a collection of equal-length named series. Like a
series it is a wrapper value (@racket[dataframe?]) carrying the column data; it
prints as a Polars table, so @racket[display] (or @racket[~a], or the REPL)
renders it with no separate display call.

@defproc[(dataframe? [v any/c]) boolean?]{
  Returns @racket[#t] if @racket[v] is a dataframe.}

@defproc[(dataframe [columns (listof series?)]) dataframe?]{
  Builds a dataframe from a list of equal-length series. The columns may be
  series wrappers built with @racket[series]; their names become the column
  names, and must differ.

  @examples[#:eval ev
(dataframe (list (series '("a" "b") #:name "k")
                 (series '(1 2) #:name "v")))
(eval:error (dataframe (list (series '(1) #:name "k") (series '(2) #:name "k"))))]}

@deftogether[(@defproc[(shape [x has-shape?]) (listof exact-nonnegative-integer?)]
              @defproc[(shape/values [x has-shape?]) (values exact-nonnegative-integer? ...)]
              @defproc[(height [d dataframe?]) exact-nonnegative-integer?]
              @defproc[(width [d dataframe?]) exact-nonnegative-integer?])]{
  @racket[shape] returns the dimensions as a list — @racket[(list rows cols)] for
  a dataframe and @racket[(list n)] for a series — mirroring Polars' shape
  tuples. @racket[shape/values] returns the same dimensions as multiple
  @racket[values], for callers that want to bind them positionally with
  @racket[let-values] or @racket[define-values]. @racket[height] and
  @racket[width] return the row and column counts of a dataframe; @racket[height]
  is also @racket[(len d)].}

@deftogether[(@defproc[(column-names [d dataframe?]) (listof string?)]
              @defproc[(column-name [d dataframe?] [i exact-nonnegative-integer?]) string?])]{
  @racket[column-names] returns all column names in order; @racket[column-name]
  returns the name of the column at index @racket[i].}

@defproc[(ref [x has-ref?]
              [key (or/c exact-nonnegative-integer? string?) _absent]
              [#:columns columns
                         (or/c exact-nonnegative-integer? string?
                               (listof (or/c exact-nonnegative-integer? string?)))
                         _absent]
              [#:rows rows any/c _absent])
         any/c]{
  The generic element / column accessor. On a series, @racket[(ref s i)] returns
  the element at index @racket[i]. On a dataframe, a single selector — given
  positionally or as @racket[#:columns] — returns that column (by name or index)
  as a series, and a @emph{list} of selectors returns a column-projected
  dataframe. It is data-first, so it threads. A name in the list is taken
  literally, never as a pattern; a name the frame lacks, or a column selected
  twice, raises. @racket[#:rows] is reserved for
  row slicing and currently raises an error. Provided by the @racket[gen:has-ref]
  interface. For a whole column, @racket[series->list] and its siblings convert
  in one pass where a @racket[ref] loop makes one foreign call per element.

  @examples[#:eval ev
(define starred (dataframe (list (series '(1) #:name "*") (series '(2) #:name "b"))))
(ref starred '("*"))
(eval:error (ref starred '("b" 1)))]}

@defproc[(describe [x (or/c series? dataframe?)]) dataframe?]{
  Mirrors Polars' @tt{.describe()}: returns a summary-statistics @tech{dataframe}
  (which prints as a table). For a series the result has a @racket["statistic"]
  column and a @racket["value"] column, with rows adapted to the dtype — a
  numeric series gets @racket["count"], @racket["null_count"], @racket["mean"],
  @racket["std"], @racket["min"], @racket["25%"], @racket["50%"], @racket["75%"]
  and @racket["max"]; a temporal series (date, datetime, time, duration) drops
  @racket["std"]; a boolean series also drops the quantiles; a string series
  keeps @racket["count"], @racket["null_count"], @racket["min"] and
  @racket["max"]; any other dtype just the two counts. For a dataframe the
  result uses Polars' fixed nine-row layout (a @racket["statistic"] column plus
  one column per input column), leaving a cell @racket[polars-null] where a
  column has no value for that statistic.

  Numeric, boolean, null and nested columns summarise as @racket['float64],
  every other column as strings; temporal values are written as Python prints
  them, a zoned datetime as its local time and UTC offset. Quantiles use
  nearest interpolation. Every statistic of every column comes from one
  query, so Polars computes the columns in parallel.

  API gap: a binary column gets no @racket["min"] or @racket["max"].

  Numeric, string and boolean columns, with nulls:

  @examples[#:eval ev #:label #f
(define flights
  (dataframe
   (list (series (list "UA" "AA" "UA" polars-null) #:name "carrier")
         (series (list 1400 733 polars-null 1089) #:name "distance")
         (series (list #t #f #t #t) #:name "on_time"))))
(describe flights)]

  Datetime, duration and date columns get a mean and quartiles; a date
  column's mean is a datetime:

  @examples[#:eval ev #:label #f
(define times
  (~> (dataframe
       (list (series (list (datetime 2013 1 1 5) (datetime 2013 1 1 6)
                           (datetime 2013 1 2 7) (datetime 2013 1 3 8))
                     #:name "scheduled")
             (series (list (datetime 2013 1 1 5 12) (datetime 2013 1 1 5 57)
                           polars-null (datetime 2013 1 3 9 30))
                     #:name "departed")))
      (with-columns (alias (- (col "departed") (col "scheduled")) "delay")
                    (alias (cast "scheduled" 'date) "day"))))
(describe times)]

  A zoned datetime column's statistics carry the offset in force at each:

  @examples[#:eval ev #:label #f
(describe (series (list (moment 2021 3 27 12 #:tz "Europe/Brussels")
                        (moment 2021 7 1 #:tz "Europe/Brussels"))
                  #:name "local"))]

  A series keeps only the rows its dtype has:

  @examples[#:eval ev #:label #f
(describe (series (list 3 1 polars-null 4 1 5) #:name "n"))
(describe (ref times "day"))]

  A nested column (here the lists @racket[agg] collects) and a null-dtype
  column report only their counts, as floats; a frame with no rows reports
  zero counts:

  @examples[#:eval ev #:label #f
(~> flights (group-by "carrier") (agg (col "distance")) describe)
(~> flights (select (alias (cast "carrier" 'null) "nothing")) describe)
(describe (head flights 0))]}

@subsection[#:tag "ref-dataframe-convert"]{Converting to Racket values}

@defproc[(dataframe->columns [d dataframe?]
                             [#:columns columns (listof string?) (column-names d)]
                             [#:null null-value any/c polars-null])
         (listof (cons/c string? vector?))]{
  Returns each selected column, in the order of @racket[columns], paired with
  @racket[(series->vector column #:null null-value)]. Mirrors Polars'
  @tt{DataFrame.to_dict(as_series=False)}. An unknown or repeated name, or a
  column of an unsupported dtype, raises @racket[exn:fail:contract] naming the
  column.

  @examples[#:eval ev #:label #f
(define kv (dataframe (list (series '("a" "b") #:name "k")
                            (series (list 1 polars-null) #:name "v"))))
(dataframe->columns kv)
(dataframe->columns kv #:columns '("v" "k") #:null 0)
(eval:error (dataframe->columns kv #:columns '("k" "k")))
(eval:error (dataframe->columns kv #:columns '("nope")))]}

@defproc[(dataframe->hash [d dataframe?]
                          [#:columns columns (listof string?) (column-names d)]
                          [#:null null-value any/c polars-null])
         (and/c (hash/c string? vector?) immutable?)]{
  Like @racket[dataframe->columns], but returns an immutable hash from each
  selected column's name to its vector, as Polars' @tt{DataFrame.to_dict()} gives
  a dict. The same names are checked and the same errors raised.

  @examples[#:eval ev #:label #f
(dataframe->hash kv)
(hash-ref (dataframe->hash kv #:null 0) "v")
(dataframe->hash kv #:columns '("k"))
(eval:error (dataframe->hash kv #:columns '("nope")))]}

@defproc[(in-dataframe-columns [d dataframe?]
                               [#:columns columns (listof string?) (column-names d)])
         sequence?]{
  Returns a sequence of the selected columns of @racket[d], in the order of
  @racket[columns], each as a @tech{series} named after its column, as Polars'
  @tt{DataFrame.iter_columns()} does. Each column is fetched when the sequence
  reaches it, and is released once nothing refers to it. An unknown or repeated
  name raises @racket[exn:fail:contract] naming the column. The dataframe itself
  is not a sequence.

  @examples[#:eval ev #:label #f
(for/list ([column (in-dataframe-columns kv)]) (series-name column))
(for/list ([column (in-dataframe-columns kv #:columns '("v"))])
  (series->list column #:null 0))
(for/first ([column (in-dataframe-columns kv)]) column)
(eval:error (in-dataframe-columns kv #:columns '("k" "k")))]}

@defproc[(in-dataframe-rows [d dataframe?]
                            [#:columns columns (listof string?) (column-names d)]
                            [#:named? named? boolean? #f]
                            [#:null null-value any/c polars-null]
                            [#:buffer-size buffer-size exact-positive-integer? 512])
         sequence?]{
  Returns a sequence of the rows of @racket[d], as Polars'
  @tt{DataFrame.iter_rows()} does. Each row holds the selected columns in the
  order of @racket[columns]: a fresh mutable vector of their values, or, when
  @racket[named?] is true, an immutable hash from each column's name to its
  value, as @tt{iter_rows(named=True)} gives a dict. A value is what
  @racket[ref] returns, as in @secref["ref-series-convert"], with
  @racket[null-value] in place of a null. With no columns, each row is empty.

  The rows are converted @racket[buffer-size] at a time, as
  @tt{buffer_size} does: each buffer is one bulk copy per column, never a
  foreign call per value. A loop holds one buffer's values at a time, so memory
  stays bounded for any height, and one that stops early converts at most one
  buffer beyond the rows it reads. A larger buffer makes fewer calls and holds
  more values.

  The columns are fetched and checked when @racket[in-dataframe-rows] is
  called: an unknown or repeated name, or a column of an unsupported dtype,
  raises @racket[exn:fail:contract] naming the column. The sequence holds those
  columns rather than @racket[d], and each iteration starts from the first row.
  A lazyframe is not accepted; @racket[collect] it first. Python's
  @tt{buffer_size=0}, a row at a time, has no counterpart.

  @examples[#:eval ev #:label #f
(define trips
  (dataframe (list (series '(UA AA UA) #:name "carrier")
                   (series (list 2 polars-null -3) #:name "delay")
                   (cast (series (list (datetime 2013 1 1) (datetime 2013 1 1)
                                       (datetime 2013 1 2))
                                 #:name "day")
                         'date))))
(for/list ([row (in-dataframe-rows trips)]) row)
(for/list ([row (in-dataframe-rows trips #:columns '("delay" "carrier") #:named? #t)])
  row)
(for/sum ([row (in-dataframe-rows trips #:columns '("delay") #:null 0)])
  (vector-ref row 0))
(for/list ([row (in-dataframe-rows trips #:buffer-size 2)])
  (define-values (carrier delay day) (vector->values row))
  (list carrier (date->iso8601 day)))
(eval:error (in-dataframe-rows trips #:columns '("nope")))
(eval:error (in-dataframe-rows trips #:buffer-size 0))]}

@defproc[(dataframe->rows [d dataframe?]
                          [#:columns columns (listof string?) (column-names d)]
                          [#:named? named? boolean? #f]
                          [#:null null-value any/c polars-null])
         (listof (or/c vector? (and/c hash? immutable?)))]{
  Returns every row of @racket[d] in a list, each as @racket[in-dataframe-rows]
  gives it: Polars' @tt{DataFrame.rows()}, and with @racket[named?] true
  @tt{DataFrame.rows(named=True)}, which is @tt{DataFrame.to_dicts()}. The same
  names are checked and the same errors raised.

  @examples[#:eval ev #:label #f
(dataframe->rows trips)
(dataframe->rows trips #:columns '("carrier") #:named? #t)
(dataframe->rows (head trips 0))
(eval:error (dataframe->rows trips #:columns '("day" "day")))]}

@defproc[(dataframe->f64vector [d dataframe?]
                               [#:columns columns (listof string?) (column-names d)]
                               [#:order order (or/c 'fortran 'c) 'fortran]
                               [#:null null-value (or/c real? 'error) +nan.0])
         (values f64vector? exact-nonnegative-integer? exact-nonnegative-integer?)]{
  Copies the selected columns into one fresh @racket[f64vector] and returns it
  with its row and column counts, mirroring Polars' @tt{DataFrame.to_numpy()}.
  With @racket['fortran] (column-major, the default) row @racket[i] of column
  @racket[j] is at index @racket[(+ (* j nrows) i)]; with @racket['c]
  (row-major) it is at @racket[(+ (* i ncols) j)]. Each column converts as by
  @racket[series->f64vector]. Every column's dtype is checked before anything is
  copied, and a column that is not numeric raises naming the column and its
  dtype. With @racket['error], a null raises naming the first column in
  @racket[columns] that has one, and that column's first null row. As with
  @racket[series->f64vector], the buffer may move: hand it only to a foreign
  call that is not @racket[#:blocking?].

  @examples[#:eval ev #:label #f
(define xy (dataframe (list (series (list 1 2 polars-null) #:name "a")
                            (series '(0.5 1.5 2.5) #:name "b"))))
(define-values (m nrows ncols) (dataframe->f64vector xy))
(list nrows ncols)
(f64vector->list m)
(define-values (m/f rows/f cols/f) (dataframe->f64vector xy #:order 'fortran))
(equal? (f64vector->list m/f) (f64vector->list m))
(define-values (m/c rows/c cols/c) (dataframe->f64vector xy #:order 'c))
(f64vector->list m/c)
(define-values (b rows/b cols/b) (dataframe->f64vector xy #:columns '("b") #:null 'error))
(f64vector->list b)
(define-values (z rows/z cols/z) (dataframe->f64vector xy #:null 0))
(f64vector->list z)
(eval:error (dataframe->f64vector xy #:null 'error))
(eval:error (dataframe->f64vector (dataframe (list (series '("p") #:name "s")))))]}

@subsection{Low-level DataFrame API}

The generic layer above is built on a set of monomorphic @tt{dataframe-*}
bindings that operate directly on the foreign dataframe. They remain exported
and accept the @racket[dataframe] wrapper (it marshals transparently); the
generic operations are simply the preferred surface.

@deftogether[(@defproc[(dataframe-new [columns (listof series?)]) dataframe?]
              @defproc[(dataframe-shape [d dataframe?])
                       (values exact-nonnegative-integer? exact-nonnegative-integer?)]
              @defproc[(dataframe-height [d dataframe?]) exact-nonnegative-integer?]
              @defproc[(dataframe-width [d dataframe?]) exact-nonnegative-integer?]
              @defproc[(dataframe-column [d dataframe?] [name string?]) series?]
              @defproc[(dataframe-column-name [d dataframe?]
                                              [i exact-nonnegative-integer?]) string?]
              @defproc[(dataframe-column-names [d dataframe?]) (listof string?)]
              @defproc[(dataframe-select [d dataframe?] [names (listof string?)]) dataframe?]
              @defproc[(display-dataframe [d dataframe?]
                                          [out output-port? (current-output-port)]) void?])]{
  The low-level dataframe operations underlying @racket[dataframe], @racket[shape],
  @racket[height], @racket[width], @racket[ref], @racket[column-name], and
  @racket[column-names]. @racket[display-dataframe] prints the Polars table to
  @racket[out]; since a @racket[dataframe] now prints itself, prefer plain
  @racket[display]. @racket[dataframe-column] raises an error naming the
  column when @racket[d] has none. @racket[display-dataframe] raises with
  Polars' reason when Polars cannot print the table, where the dataframe
  itself prints as a placeholder.

  @examples[#:eval ev
(define scores (dataframe (list (series '(10 25 18) #:name "score" #:dtype 'i32))))
(series-sum-i32 (dataframe-column scores "score"))
(eval:error (dataframe-column scores "points"))
(dataframe (list far-date))
(eval:error (display-dataframe (dataframe (list far-date))))]}

@defproc[(DataFrame-ptr? [v any/c]) boolean?]{
  Recognises a foreign dataframe pointer. Both raw pointers returned by the
  low-level operations and @racket[dataframe] wrappers satisfy it.}

@defproc[(dataframe-drop [d DataFrame-ptr?]) void?]{
  Releases the native frame @racket[d] holds now, as @racket[series-drop]
  releases a series. A dropped frame still answers to @racket[dataframe?]
  and @racket[DataFrame-ptr?] and prints as
  @racketresultfont{#<dataframe: dropped>}, and any later use raises
  @racket[exn:fail:contract]: dropping it again names
  @racket[dataframe-drop], and any other use names the frame, as
  @racketerror{dataframe: dataframe has been dropped}. As for a series, a
  drop must not run while another thread uses the same frame.

  @examples[#:eval ev
(define readings (dataframe (list (series '(3 1 2) #:name "v"))))
(dataframe-drop readings)
readings
(eval:error (height readings))
(eval:error (dataframe-drop readings))]}

@defproc[(dataframe-vstack [top DataFrame-ptr?] [bottom DataFrame-ptr?]) DataFrame-ptr?]{
  Stacks the rows of @racket[bottom] beneath those of @racket[top], which must
  have the same columns in the same order, and returns the combined frame
  (Polars' @tt{vstack}). The fluent @racket[vstack] is the wrapper-returning
  equivalent.}

@defproc[(dataframe-sort [d DataFrame-ptr?]
                         [names (non-empty-listof string?)]
                         [#:descending descending (or/c boolean? (listof boolean?)) #f]
                         [#:nulls-last nulls-last (or/c boolean? (listof boolean?)) #f]
                         [#:maintain-order maintain-order boolean? #f])
         DataFrame-ptr?]{
  Returns @racket[d] sorted by the columns @racket[names]; the fluent
  @racket[sort] on a dataframe wraps it, and its entry describes the keywords.
  A column absent from @racket[d] raises @racket[exn:fail].}

@subsection[#:tag "ref-reading-writing"]{Reading & writing}

@deftogether[(@defproc/arguments[parquet-read-arguments
                                 (dataframe-read-parquet [path path-string?] DataFrame-ptr?)]
              @defproc/arguments[parquet-scan-arguments
                                 (lazyframe-scan-parquet [path path-string?] LazyFrame-ptr?)]
              @defproc/arguments[parquet-write-arguments
                                 (dataframe-write-parquet [frame DataFrame-ptr?]
                                                          [path path-string?]
                                                          void?)])]{
  The raw-pointer reader, scan and writer under @racket[read-parquet],
  @racket[scan-parquet] and @racket[write-parquet], with the same keywords
  and checks.

  @examples[#:eval ev
(dataframe-height (dataframe-read-parquet "flights.parquet" #:n-rows 5))
(dataframe-width (lazyframe-collect (lazyframe-scan-parquet "produce.parquet")))
(dataframe-write-parquet (dataframe-read-parquet "produce.parquet")
                         (build-path parquet-dir "raw.parquet")
                         #:compression 'snappy)
(dataframe-height (dataframe-read-parquet (build-path parquet-dir "raw.parquet")))
(eval:error (dataframe-read-parquet "produce.parquet" #:columns '(3)))
(eval:error (lazyframe-scan-parquet "produce.parquet" #:missing-columns 'ignore))
(eval:error (dataframe-write-parquet (dataframe-read-parquet "produce.parquet")
                                     (build-path parquet-dir "raw.parquet")
                                     #:compression 'lzo))]

  @examples[#:eval ev #:hidden
(delete-directory/files parquet-dir)]}

@deftogether[(@defproc/arguments[csv-read-arguments (dataframe-read-csv [path path-string?] DataFrame-ptr?)]
              @defproc/arguments[csv-scan-arguments (lazyframe-scan-csv [path path-string?] LazyFrame-ptr?)]
              @defproc/arguments[csv-write-arguments
                                 (dataframe-write-csv [frame DataFrame-ptr?] [path path-string?] void?)])]{
  The raw-pointer reader, scan and writer under @racket[read-csv],
  @racket[scan-csv] and @racket[write-csv], with the same keywords and
  checks; a failure names these.

  @examples[#:eval ev
(dataframe-height (dataframe-read-csv "flights.tsv" #:separator #\tab #:null-values "NA"))
(dataframe-height (lazyframe-collect (lazyframe-scan-csv "parts/*.csv")))
(eval:error (dataframe-read-csv "parts/part-1.csv" #:columns '("origin" "gate")))
(eval:error (dataframe-write-csv (dataframe-read-csv "parts/part-1.csv")
                                 "/no/such/dir/out.csv" #:separator #\;))]}

@deftogether[(@defproc/arguments[json-arguments (dataframe-read-json [path path-string?] DataFrame-ptr?)]
              @defproc[(dataframe-write-json [d DataFrame-ptr?] [path path-string?]) void?])]{
  The raw-pointer JSON-array reader and writer under @racket[read-json] and
  @racket[write-json], with the same keywords and checks.

  @examples[#:eval ev
(dataframe-width (dataframe-read-json "stations.json" #:schema '(("station" . str))))
(eval:error (dataframe-read-json "stations.json" #:infer-schema-length 0))]}

@deftogether[(@defproc/arguments[ndjson-arguments (dataframe-read-json-lines [path path-string?] DataFrame-ptr?)]
              @defproc/arguments[ndjson-arguments (lazyframe-scan-json-lines [path path-string?] LazyFrame-ptr?)]
              @defproc/arguments[ndjson-writer-arguments (dataframe-write-json-lines [d DataFrame-ptr?] [path path-string?] void?)])]{
  The raw-pointer NDJSON reader, scan and writer under @racket[read-ndjson],
  @racket[scan-ndjson] and @racket[write-ndjson], with the same keywords and
  checks.

  @examples[#:eval ev
(dataframe-height (dataframe-read-json-lines "stations.ndjson" #:n-rows 3))
(dataframe-width (lazyframe-collect (lazyframe-scan-json-lines "stations.ndjson"
                                                               #:infer-schema-length 2)))
(eval:error (dataframe-read-json-lines "stations.ndjson" #:schema '(("reading" . i8))))]}

@section[#:tag "ref-lazy"]{Lazy frames}

A @deftech{lazyframe} is a query plan: a sequence of operations over a frame
that Polars optimises as a whole and runs only when asked to collect. The
low-level surface mirrors the eager @tt{dataframe-*} bindings and, like them,
returns raw foreign pointers; the fluent @racket[lazy] and @racket[collect]
are the wrapper-returning equivalents.

@deftogether[(@defproc[(LazyFrame-ptr? [v any/c]) boolean?]
              @defproc[(lazyframe? [v any/c]) boolean?])]{
  @racket[LazyFrame-ptr?] recognises a foreign lazyframe pointer, raw or
  wrapped. @racket[lazyframe?] recognises only the wrapper produced by the
  fluent @racket[lazy].}

@defproc[(lazyframe-drop [lf LazyFrame-ptr?]) void?]{
  Releases the native plan @racket[lf] holds now, as @racket[series-drop]
  releases a series. A dropped plan still answers to @racket[lazyframe?]
  and @racket[LazyFrame-ptr?] and prints as
  @racketresultfont{#<lazyframe: dropped>}, and any later use raises
  @racket[exn:fail:contract]: dropping it again names
  @racket[lazyframe-drop], and any other use names the plan, as
  @racketerror{lazyframe: lazyframe has been dropped}. As for a series, a
  drop must not run while another thread uses the same plan.

  @examples[#:eval ev
(define query (lazy (dataframe (list (series '(3 1 2) #:name "v")))))
(lazyframe-drop query)
query
(eval:error (collect query))
(eval:error (lazyframe-drop query))]}

@deftogether[(@defproc[(dataframe-lazy [df DataFrame-ptr?]) LazyFrame-ptr?]
              @defproc[(lazyframe-collect [lf LazyFrame-ptr?]) DataFrame-ptr?])]{
  @racket[dataframe-lazy] starts a plan from an in-memory frame
  (@tt{df.lazy()}); @racket[lazyframe-collect] executes a plan and returns the
  resulting frame (@tt{lf.collect()}).}

@defproc[(lazyframe-explain [lf LazyFrame-ptr?]
                            [#:optimized optimized boolean? #t]
                            [#:format format (or/c 'plain 'tree) 'plain])
         string?]{
  The plan under @racket[explain], which wraps it.

  @examples[#:eval ev
(displayln (lazyframe-explain (dataframe-lazy (dataframe-read-parquet "produce.parquet"))))
(eval:error (lazyframe-explain
             (lazyframe-select (dataframe-lazy (dataframe-read-parquet "produce.parquet"))
                               (list (col "colour")))))]}

@deftogether[(@defproc[(lazyframe-select       [lf LazyFrame-ptr?] [exprs (listof Expr-ptr?)]) LazyFrame-ptr?]
              @defproc[(lazyframe-with-columns [lf LazyFrame-ptr?] [exprs (listof Expr-ptr?)]) LazyFrame-ptr?]
              @defproc[(lazyframe-filter       [lf LazyFrame-ptr?] [predicate Expr-ptr?]) LazyFrame-ptr?]
              @defproc[(lazyframe-group-by-agg [lf LazyFrame-ptr?]
                                               [keys (listof (or/c string? Expr-ptr?))]
                                               [aggs (listof Expr-ptr?)]) LazyFrame-ptr?])]{
  The lazy forms of the @secref["ref-expr-contexts"]. Each appends a step to
  the plan and returns the extended plan; nothing runs until
  @racket[lazyframe-collect].}

@defproc[(lazyframe-sort [lf LazyFrame-ptr?]
                         [names (non-empty-listof string?)]
                         [#:descending descending (or/c boolean? (listof boolean?)) #f]
                         [#:nulls-last nulls-last (or/c boolean? (listof boolean?)) #f]
                         [#:maintain-order maintain-order boolean? #f])
         LazyFrame-ptr?]{
  Appends a sort by the columns @racket[names] to the plan; the fluent
  @racket[sort] on a lazyframe wraps it. An absent column is reported at
  @racket[lazyframe-collect].}

@defproc[(lazyframe-join [left LazyFrame-ptr?]
                         [right LazyFrame-ptr?]
                         [#:on on (or/c #f (non-empty-listof utf-8-name/c)) #f]
                         [#:left-on left-on (or/c #f (non-empty-listof utf-8-name/c)) #f]
                         [#:right-on right-on (or/c #f (non-empty-listof utf-8-name/c)) #f]
                         [#:how how (or/c 'inner 'left 'outer 'full 'cross 'semi 'anti) 'inner])
         LazyFrame-ptr?]{
  Joins two plans. Give the key columns either as one list with @racket[#:on],
  when they have the same names on both sides, or as parallel
  @racket[#:left-on] and @racket[#:right-on] lists of @racket[utf-8-name/c]
  names. @racket[#:how] selects the join kind; @racket['outer] and
  @racket['full] are synonyms, and a @racket['cross] join takes no keys.
  Omitting the keys for any other kind is an error. Collect the result with
  @racket[lazyframe-collect]:

  @racketblock[
  (lazyframe-collect
   (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                   #:on '("uid") #:how 'inner))
  ]}

@section[#:tag "ref-expressions"]{Low-level expression API}

The monomorphic @tt{expr-*} layer that the operators in
@secref["ref-fluent"] are built from. You rarely need these names directly:
@racket[expr-gt] underlies @racket[>], @racket[expr-add] underlies
@racket[+], @racket[expr-sum] underlies the expression arm of @racket[sum].
Reach for them when a generic name is shadowed in your module, or when you
want to be explicit that an expression --- rather than a number --- is being
built.

@defproc[(expr-alias [e Expr-ptr?] [name string?]) Expr-ptr?]{
  Names the column an expression produces, matching @tt{.alias}. The generic
  spelling is @racket[alias], which is the one to reach for:
  @racket[(alias (sum (col "value")) "total")].}

@defproc[(expr-col [name string?]) Expr-ptr?]{
  The column reference @racket[col] is built on: @racket[name] is taken
  literally, except that a name of the form @tt{^...$} is a regex
  projection, which is how the regexp arm of @racket[col] is spelled.

  @examples[#:eval ev
(expr-col "weight")
(expr-col "^.*ght$")]}

@deftogether[(@defproc[(expr-all) Expr-ptr?]
              @defproc[(expr-exclude [e multi-column-expr?]
                                     [names (non-empty-listof (or/c string? regexp?))])
                       Expr-ptr?]
              @defproc[(expr-dtype-col [dtype dtype-spec?]) Expr-ptr?])]{
  The selector leaves under @racket[all], @racket[exclude] and the dtype arm
  of @racket[col]: @tt{pl.all()}, @tt{.exclude(...)} and
  @tt{pl.col(pl.Float64)}. @racket[expr-exclude] takes its names as one
  list where the generic @racket[exclude] is variadic. A regexp
  @racket[col] needs no entry point of its own: it is @racket[expr-col]
  with the pattern rendered in Polars' @tt{^...$} form.

  @examples[#:eval ev
(expr-all)
(expr-exclude (expr-all) (list "id" #rx"^w"))
(expr-dtype-col 'f64)
(select people (expr-exclude (expr-dtype-col 'float64) (list "height")))]}

@deftogether[(@defproc[(expr-meta-output-name [e Expr-ptr?]) string?]
              @defproc[(expr-meta-root-names [e Expr-ptr?]) (listof string?)]
              @defproc[(expr-meta-eq? [a Expr-ptr?] [b Expr-ptr?]) boolean?])]{
  The expression-only forms of @racket[meta-output-name],
  @racket[meta-root-names] and @racket[meta-eq?], which are the ones to
  write: they also accept a column name.

  @examples[#:eval ev
(~> (col "a") (expr-alias "b") expr-meta-output-name)
(~> (col "a") (expr-add (col "b")) expr-meta-root-names)
(expr-meta-eq? (col "a") (expr-col "a"))]}

@defproc[(expr-over [e Expr-ptr?] [keys (listof (or/c string? Expr-ptr?))]) Expr-ptr?]{
  The window expression @racket[over] is built on (@tt{Expr.over}), taking
  its keys as one list where @racket[over] is variadic.

  @examples[#:eval ev
(~> (col "v") expr-sum (expr-over (list "k" (col "h"))))
(~> khv (with-columns (~> (col "v") expr-sum (expr-over (list "k")) (expr-alias "total"))))]}

@deftogether[(@defproc[(expr-add [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-sub [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-mul [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-div [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-mod [a any/c] [b any/c]) Expr-ptr?])]{
  Element-wise arithmetic. At least one operand is normally an expression;
  the other may be a scalar, which is lifted with @racket[lit]. The generic
  @racket[+], @racket[-], @racket[*] and @racket[/] dispatch to these when
  given an expression and are the preferred surface, so write
  @racket[(* (col "value") 2)] --- which reads like @tt{col("value") * 2} ---
  rather than calling @racket[expr-mul] directly.}

@defproc[(expr-neg [e Expr-ptr?]) Expr-ptr?]{
  Negates a numeric expression (@tt{-e}); one-argument @racket[-] dispatches
  to it.

  @examples[#:eval ev #:label #f
(~> (dataframe (list (series '(1 -2 3) #:name "x")))
    (select (expr-neg (col "x"))))]}

@deftogether[(@defproc[(expr-gt [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-lt [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-ge [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-le [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-eq [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-ne [a any/c] [b any/c]) Expr-ptr?])]{
  Element-wise comparisons producing a boolean expression; scalars are lifted
  with @racket[lit]. The generic @racket[>], @racket[<], @racket[>=],
  @racket[<=], @racket[=] and @racket[!=] dispatch to these when given an
  expression and are the preferred surface: write
  @racket[(> (col "value") 15)] for @tt{col("value") > 15}.}

@deftogether[(@defproc[(expr-and [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-or  [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-xor [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-not [e Expr-ptr?]) Expr-ptr?])]{
  Element-wise boolean logic over boolean expressions, for combining
  predicates. The generic @racket[and], @racket[or], @racket[xor] and
  @racket[not] dispatch to these when given an expression and are the preferred
  surface: @racket[(and (> (col "value") 15) (< (col "cost") 3.0))].}

@deftogether[(@defproc[(expr-sum      [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-mean     [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-min      [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-max      [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-median   [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-count    [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-n-unique [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-first    [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-last     [e Expr-ptr?]) Expr-ptr?]
              @defproc[(expr-std [e Expr-ptr?] [#:ddof ddof uint8/c 1]) Expr-ptr?]
              @defproc[(expr-var [e Expr-ptr?] [#:ddof ddof uint8/c 1]) Expr-ptr?])]{
  Aggregations. Each reduces the column @racket[e] evaluates to — over the
  whole frame in a @emph{select}, or per group inside @emph{group_by/agg}.
  @racket[expr-count] counts the non-null entries, as Polars' @tt{.count()}
  does. @racket[expr-std] and @racket[expr-var] take a @racket[#:ddof]
  degrees-of-freedom adjustment, defaulting to 1; Polars holds it in a byte,
  so a value past 255 is a contract error. The generic @racket[sum],
  @racket[mean], @racket[min], @racket[max], @racket[median], @racket[count],
  @racket[n-unique], @racket[first], @racket[last], @racket[std] and
  @racket[var] dispatch to these when given an expression or a column name.

  @examples[#:eval ev
(~> (dataframe (list (series '(2.0 4.0 4.0 6.0) #:name "v")))
    (select (expr-alias (expr-std (col "v") #:ddof 0) "s")))
(eval:error (expr-std (col "v") #:ddof 256))]}

@deftogether[(@defproc[(expr-sort [e Expr-ptr?]
                                  [#:descending descending boolean? #f]
                                  [#:nulls-last nulls-last boolean? #f])
                       Expr-ptr?]
              @defproc[(expr-sort-by [e Expr-ptr?]
                                     [#:by by (or/c string? Expr-ptr?
                                                    (non-empty-listof (or/c string? Expr-ptr?)))]
                                     [#:descending descending (or/c boolean? (listof boolean?)) #f]
                                     [#:nulls-last nulls-last (or/c boolean? (listof boolean?)) #f]
                                     [#:maintain-order maintain-order boolean? #f])
                       Expr-ptr?])]{
  The expression-only forms under @racket[sort] on an expression and
  @racket[sort-by]. Write those instead: they also accept a column name.}

@subsection[#:tag "ref-expr-contexts"]{Eager expression contexts}

These run expressions against a @tech{dataframe} and return a new frame in one
step. Each is the eager convenience over the corresponding lazy operation in
@secref["ref-lazy"]: it converts with @racket[dataframe-lazy], applies the
operation, and @racket[lazyframe-collect]s. Like the rest of the low-level
layer they accept a @racket[dataframe] wrapper but return a raw
@racket[DataFrame-ptr?]; the fluent @racket[select], @racket[with-columns],
@racket[filter] and @racket[group-by]/@racket[agg] are the wrapper-returning
equivalents.

@deftogether[(@defproc[(dataframe-select-exprs [df DataFrame-ptr?] [exprs (listof Expr-ptr?)]) DataFrame-ptr?]
              @defproc[(dataframe-with-columns [df DataFrame-ptr?] [exprs (listof Expr-ptr?)]) DataFrame-ptr?]
              @defproc[(dataframe-filter-expr  [df DataFrame-ptr?] [predicate Expr-ptr?]) DataFrame-ptr?])]{
  @racket[dataframe-select-exprs] evaluates @racket[exprs] and returns a frame
  containing only the resulting columns (@tt{df.select(...)}).
  @racket[dataframe-with-columns] evaluates them and adds (or replaces) the
  resulting columns alongside the existing ones (@tt{df.with_columns(...)}).
  @racket[dataframe-filter-expr] keeps the rows for which the boolean
  @racket[predicate] holds (@tt{df.filter(...)}).}

@defproc[(dataframe-group-by-agg [df DataFrame-ptr?]
                                 [keys (listof (or/c string? Expr-ptr?))]
                                 [aggs (listof Expr-ptr?)])
         DataFrame-ptr?]{
  Groups @racket[df] by @racket[keys] — column names, or expressions — and
  evaluates each aggregation in @racket[aggs] once per group, returning a frame
  with one row per group (@tt{df.group_by(...).agg(...)}). The row order of the
  result is not guaranteed.}

@section[#:tag "ref-generic-interfaces"]{Generic interfaces}

The high-level operations are small, purpose-named
@racketmodname[racket/generic] interfaces. A wrapper implements the interface
for each capability it has — a series and a dataframe both have a @racket[len]
and a @racket[shape], so both implement @racket[gen:sized] and
@racket[gen:has-shape]; only a series has a @racket[dtype]. Each interface
exports its method(s) and a predicate that recognises values implementing it.

@deftogether[(@defidform[gen:has-ref]
              @defproc[(has-ref? [v any/c]) boolean?])]{
  The @racket[ref] capability (method: @racket[ref]). Implemented by series and
  dataframes.}

@deftogether[(@defidform[gen:sized]
              @defproc[(sized? [v any/c]) boolean?])]{
  The @racket[len] capability (method: @racket[len]). Implemented by series
  (number of elements) and dataframes (number of rows).}

@deftogether[(@defidform[gen:has-shape]
              @defproc[(has-shape? [v any/c]) boolean?])]{
  The @racket[shape] capability (method: @racket[shape]). Implemented by series
  and dataframes.}

@deftogether[(@defidform[gen:has-dtype]
              @defproc[(has-dtype? [v any/c]) boolean?])]{
  The @racket[dtype] capability (method: @racket[dtype]). Implemented by series.}

@deftogether[(@defidform[gen:has-null-count]
              @defproc[(has-null-count? [v any/c]) boolean?])]{
  The @racket[null-count] capability (method: @racket[null-count]). Implemented
  by series.}

A series is also a Racket sequence (through @racket[prop:sequence]): a
@racket[for] clause, @racket[sequence?] and the @racketmodname[racket/sequence]
operations see its elements, converted a block of rows at a time as by
@racket[in-series], with @racket[polars-null] for a null entry. A dataframe is
not a sequence; iterate over its rows with @racket[in-dataframe-rows] or its
columns with @racket[in-dataframe-columns], or convert them with
@racket[dataframe->rows] or @racket[dataframe->columns].

@examples[#:eval ev #:label #f
(define ages (series (list 34 polars-null 51) #:name "age"))
(sequence? ages)
(for/list ([age ages]) age)
(for/sum ([age ages] #:unless (polars-null? age)) age)
(sequence? (dataframe (list ages)))]

@(close-eval ev)
