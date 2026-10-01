#lang scribble/manual
@(require "utils.rkt"
          racket/runtime-path
          syntax/parse/define
          (for-syntax racket/base syntax/strip-context))

@(define-runtime-path data-dir "data")
@(define ev (make-polars-eval #:directory data-dir))

@(begin-for-syntax
   (define csv-arguments
     (quote-syntax
      ([path path-string?]
       [#:has-header has-header boolean? #t]
       [#:separator separator (or/c csv-char/c #f) #f]
       [#:quote-char quote-char (or/c csv-char/c #f) #\"]
       [#:comment-prefix comment-prefix (or/c non-empty-string? #f) #f]
       [#:skip-rows skip-rows exact-nonnegative-integer? 0]
       [#:n-rows n-rows (or/c exact-nonnegative-integer? #f) #f]
       [#:null-values null-values (or/c string? (listof string?) #f) #f]
       [#:infer-schema-length infer-schema-length (or/c exact-nonnegative-integer? #f) 100]
       [#:schema-overrides schema-overrides
                           (and/c (listof (cons/c string? csv-dtype/c)) distinct-names?)
                           '()]
       [#:ignore-errors ignore-errors boolean? #f]
       [#:try-parse-dates try-parse-dates boolean? #f]
       [#:encoding encoding (or/c 'utf8 'utf8-lossy) 'utf8]
       [#:glob glob boolean? #t]))))

@(define-syntax-parser defcsvproc
   [(_ (name result) body ...)
    #:with (argument ...) (replace-context #'name csv-arguments)
    #'(defproc (name argument ...) result body ...)])

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

@defproc[(Expr-ptr? [v any/c]) boolean?]{
  Returns @racket[#t] if @racket[v] is an @tech{expression}.}

@deftogether[(@defproc[(col [spec (or/c string? regexp? dtype-spec?)]) Expr-ptr?]
              @defproc[(lit [v (or/c boolean? exact-integer? real? string? symbol?)]) Expr-ptr?]
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
      alike. A bare @racket['datetime] means microseconds, so match a
      column @racket[series] built from gregor datetimes with
      @racket['(datetime milliseconds)] or with its @racket[dtype].
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
      lookaround, backreferences, atomic groups or conditionals; a
      regexp using them is rejected at @racket[collect]. To select by
      such a regexp, match @racket[column-names] in Racket and select
      the names, as in the last example below.}]

  A multi-column @racket[col] expands inside any expression to one output
  per matched column, in the frame's column order, each keeping the
  matched column's name; a frame with no match yields no columns.

  @racket[lit] lifts a Racket scalar to a literal expression: booleans,
  exact integers (32-bit when they fit, 64-bit otherwise), other reals (as
  @racket['float64]) and strings. A symbol is the string of its name, so a
  categorical column compares with the symbols it reads back as. Every
  operator below lifts a
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
(eval:error (select people (col #px"^(?!id)")))
(select people (filter (lambda (name) (regexp-match? #px"^(?!id)" name))
                       (column-names people)))]}

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
  @racket[col] prints as the Polars pattern it is translated to.

  @examples[#:eval ev
(col "weight")
(alias (* (col "v") 10) "v10")
(expr->string (> (col "v") 2))
(~> (col "v") sum (over "k"))
(exclude (all) "id")
(col 'float64)
(col #rx"^he")]}

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
  @racket[(not (= _a _b))]. These shadow the @racketmodname[racket/base]
  comparisons; see @secref["fluent-shadowing"].}

@deftogether[(@defform[(and expr ...)]
              @defform[(or expr ...)]
              @defproc[(not [x any/c]) any/c]
              @defproc[(xor [a any/c] [b any/c]) any/c])]{
  Overloaded boolean connectives. When an operand is an expression they build
  the element-wise expression (@racket[expr-and], @racket[expr-or],
  @racket[expr-not], @racket[expr-xor]), so
  @racket[(and (> (col "value") 15) (< (col "cost") 3.0))] is a predicate for
  @racket[filter]. When an operand is a series they compute an eager boolean
  mask. Otherwise they behave as the @racketmodname[racket/base] forms:
  @racket[and] and @racket[or] short-circuit and return the deciding value, and
  @racket[not] negates. Note that once @racket[and] or @racket[or] meets an
  expression or series operand it evaluates its remaining operands eagerly to
  combine them. These shadow the @racketmodname[racket/base] bindings; see
  @secref["fluent-shadowing"].}

@deftogether[(@defproc[(+ [v any/c] ...) any/c]
              @defproc[(- [v any/c] ...) any/c]
              @defproc[(* [v any/c] ...) any/c]
              @defproc[(/ [v any/c] ...) any/c])]{
  Overloaded arithmetic. When every argument is a number they are exactly the
  @racketmodname[racket/base] operators. Otherwise they fold left over the
  arguments: an expression operand yields an expression (via
  @racket[expr-add], @racket[expr-sub], @racket[expr-mul], @racket[expr-div]),
  so @racket[(* (col "value") 2)] reads like @tt{col("value") * 2}, and a
  series operand yields an eagerly computed series. A single non-numeric
  argument is returned unchanged. These shadow the @racketmodname[racket/base]
  bindings; see @secref["fluent-shadowing"].}

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
                  [#:key extract-key (or/c #f (any/c . -> . any/c)) #f]
                  [#:cache-keys? cache-keys? boolean? #f])
            list?])]{
  Sorts a @tech{dataframe} or @tech{lazyframe} by the column or columns
  @racket[by] (@tt{df.sort}), or a series by its values (@tt{Series.sort}).
  Given an @tech{expression}, or a column name lifted with @racket[col], it
  builds the expression that sorts that one column (@tt{Expr.sort}).

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

  On a list, @racket[sort] is @racketmodname[racket/base]'s, and passing it
  one of the Polars keywords is a contract violation.

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
(select flights (sort "delay" #:nulls-last #t))
(sort '(3 1 2) <)
(eval:error (sort '(3 1 2) < #:descending #t))]}

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

@defproc[(cast [x (or/c Expr-ptr? series? string?)] [dtype (or/c symbol? pair?)])
         (or/c Expr-ptr? series?)]{
  Changes dtype. On an expression (or a column name, lifted with
  @racket[col]) it builds a cast expression, matching @tt{.cast}; on a series
  it converts eagerly and returns a series. @racket[dtype] takes the same
  spellings as @racket[series-cast]: unlike @racket[series]' @racket[#:dtype],
  only the canonical names (@racket['float64], @racket['int32],
  @racket['string], ...) are accepted, not the short ones (@racket['f64],
  @racket['i32], @racket['str]); given a short name the
  @exnraise[exn:fail]. A value that does not convert becomes null, except
  in a cast to an Enum, which raises naming the values outside its
  categories, as Python's default @tt{strict=True} does (on an expression,
  when the plan runs).

  @examples[#:eval ev
(~> (dataframe (list (series '(1 2 3) #:name "v")))
    (with-columns (cast "v" 'float64)))
(cast (series '("UA" "AA" "UA")) 'categorical)
(eval:error (cast (series '(1 2 3)) 'f64))
(define-enum carriers UA AA)
(eval:error (cast (series '("UA" "B6")) carriers))]}

@defproc[(vstack [top dataframe?] [bottom dataframe?]) dataframe?]{
  Stacks the rows of @racket[bottom] beneath those of @racket[top], which must
  have the same columns in the same order (Polars' @tt{vstack}).

  @examples[#:eval ev
(define top (dataframe (list (series '(1 2) #:name "v"))))
(vstack top (dataframe (list (series '(3) #:name "v"))))]}

@deftogether[(@defproc[(head [x (or/c series? dataframe? lazyframe? Expr-ptr?)]
                             [n exact-nonnegative-integer?]) any/c]
              @defproc[(tail [x (or/c series? dataframe? lazyframe? Expr-ptr?)]
                             [n exact-nonnegative-integer?]) any/c]
              @defproc[(slice [x (or/c series? dataframe? lazyframe? Expr-ptr?)]
                              [offset exact-integer?]
                              [length exact-nonnegative-integer?]) any/c])]{
  The first @racket[n] rows, the last @racket[n] rows, or @racket[length] rows
  starting at @racket[offset], of the same kind as @racket[x] (Polars'
  @tt{head}, @tt{tail}, @tt{slice}). On an expression they change the length
  and belong inside @racket[select].

  @examples[#:eval ev
(define nums (dataframe (list (series '(1 2 3 4 5) #:name "v"))))
(head nums 2)
(tail nums 2)]}

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

@defproc[(drop [d dataframe?] [names (or/c string? (listof string?))]) dataframe?]{
  Removes the named column(s) (@tt{df.drop}). Applied to a list it falls back
  to @racketmodname[racket/list]'s @racketid[drop].}

@defproc[(join [left (or/c dataframe? lazyframe?)]
               [right (or/c dataframe? lazyframe?)]
               [#:on on (or/c (listof string?) #f) #f]
               [#:left-on left-on (or/c (listof string?) #f) #f]
               [#:right-on right-on (or/c (listof string?) #f) #f]
               [#:how how (or/c 'inner 'left 'outer 'cross 'semi 'anti) 'inner])
         (or/c dataframe? lazyframe?)]{
  Joins @racket[right] onto @racket[left] on the shared key columns
  @racket[#:on], or on @racket[#:left-on] / @racket[#:right-on]
  (@tt{left.join(right, ...)}). Eager on a @tech{dataframe}, deferred on a
  @tech{lazyframe}. As in Python Polars, only a @racket['cross] join promises
  a row order; sort the result when order matters.

  @examples[#:eval ev
(define left (dataframe (list (series '("a" "b") #:name "k")
                               (series '(1 2) #:name "v"))))
(define right (dataframe (list (series '("a" "c") #:name "k")
                                (series '(10 30) #:name "w"))))
(~> (join left right #:on '("k") #:how 'left) (sort "k"))
(join left right #:on '("k") #:how 'inner)]}

@defcsvproc[(read-csv dataframe?)]{
  Reads CSV into a @tech{dataframe} (@tt{pl.read_csv}). @racket[path] may be
  a glob pattern (@litchar{*}, @litchar{?}, @litchar{[...]}): every matching
  file is read, in sorted filename order, and the files must share a header;
  @racket[#:glob #f] takes the path literally, and @litchar{[[]} matches a
  literal @litchar{[} in a pattern. A relative @racket[path] is resolved
  against @racket[current-directory], whose own name is never read as a
  pattern. A directory is an error: name its files with a pattern.

  A @racket[csv-char/c] is one ASCII character other than newline or return.
  @racket[separator] defaults to @racket[#\,]; @racket[quote-char] must
  differ from it, and @racket[#:quote-char #f] turns quoting off.
  Lines that start with @racket[comment-prefix] are skipped, as are the first
  @racket[skip-rows] lines of each file; @racket[n-rows] caps the rows read.
  A field equal to one of @racket[null-values] reads as null. Column types
  are inferred from the first @racket[infer-schema-length] rows: @racket[#f]
  reads every row, and @racket[0] makes every column a string.
  @racket[schema-overrides] fixes the named columns' types. A
  @racket[csv-dtype/c] is any spelling @racket[series]' @racket[#:dtype]
  accepts except a duration, which Polars cannot parse from CSV, and an
  Enum; API gap: read the column as @racket['categorical] or
  @racket['string] and @racket[cast] it. Each column
  appears at most once (@racket[distinct-names?]), and naming a column the
  file lacks is an error, where Python ignores the override. With
  @racket[#:ignore-errors #t] a field that does not parse reads as null. @racket[#:try-parse-dates #t] reads ISO
  dates, times of day and datetimes as @racket['date], @racket['time] and
  @racket['datetime] columns. @racket['utf8-lossy] replaces invalid UTF-8 with
  U+FFFD.

  The result is @racket[(collect (scan-csv path ....))] with the same
  keywords; as in Python, a single file is read eagerly rather than through
  a plan, which is faster. There is one extra check, stricter than Python's
  @tt{read_csv}, which returns the one column. When @racket[separator] is @racket[#f] and the
  file reads as one column whose header splits on a tab, @litchar{;} or
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
(eval:error (read-csv "parts"))]}

@defcsvproc[(scan-csv lazyframe?)]{
  Starts a @tech{lazyframe} plan from CSV without reading it
  (@tt{pl.scan_csv}); the keywords are @racket[read-csv]'s. @racket[collect]
  runs the plan, and that is where a file that cannot be read, or a glob
  pattern that matches no file, is reported. One thing is reported here
  instead: when @racket[schema-overrides] is given, a column it names that
  the header lacks, which reads the header. The separator check does not
  apply, and a directory reads every file in it.

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
                      #:schema-overrides '(("dep_dealy" . f64))))]}

@deftogether[(@defproc[(read-parquet [path path-string?]) dataframe?]
              @defproc[(scan-parquet [path path-string?]
                                     [#:n-rows n-rows (or/c exact-nonnegative-integer? #f) #f])
                       lazyframe?])]{
  Read Parquet eagerly (@tt{pl.read_parquet}), or start a plan from it
  (@tt{pl.scan_parquet}). @racket[path] is always a glob pattern: the
  matching files stack in sorted filename order, and one that matches
  nothing is an error, which @racket[scan-parquet] leaves to
  @racket[collect]. A directory reads every file in it and adds its
  @litchar{key=value} subdirectory names as columns; a single file or a
  pattern adds none, as in Python, and neither does a directory whose own
  path holds @litchar{[}, @litchar{*} or @litchar{?}, which Polars reads as
  a pattern once it is escaped. @racket[read-parquet] is
  @racket[(collect (scan-parquet path))]. API gap: no @racket[#:glob], so a
  literal @litchar{[}, @litchar{*} or @litchar{?} in a file name is spelled
  @litchar{[[]}, @litchar{[*]} or @litchar{[?]} (#36).

  Categorical, Enum and Decimal columns keep their dtypes
  (@secref["ref-categorical"]). A file Polars cannot read raises
  @racket[exn:fail] with Polars' reason, even where Polars itself panics.

  @examples[#:eval ev #:hidden
(require racket/file)
(define parquet-dir (make-temporary-directory "polars-doc-~a"))
(for ([i '(1 2 3)])
  (write-parquet (read-csv (format "parts/part-~a.csv" i))
                 (build-path parquet-dir (format "part-~a.parquet" i))))]
  @examples[#:eval ev
(read-parquet (build-path parquet-dir "*.parquet"))
(collect (scan-parquet (build-path parquet-dir "part-*.parquet") #:n-rows 3))
(read-parquet "produce.parquet")]}

@deftogether[(@defproc[(read-ndjson [path path-string?]) dataframe?]
              @defproc[(write-csv [d dataframe?] [path path-string?]) void?]
              @defproc[(write-parquet [d dataframe?] [path path-string?]) void?]
              @defproc[(write-ndjson [d dataframe?] [path path-string?]) void?])]{
  Newline-delimited JSON in (@tt{pl.read_ndjson}), and a dataframe out to
  CSV, Parquet or newline-delimited JSON (@tt{df.write_csv} and friends).
  API gap: there is no @tt{scan_ndjson}, so @racket[read-ndjson] reads one
  file and takes no glob pattern (#44).}

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

@deftogether[(@defproc[(group-by [d dataframe?] [key (or/c string? any/c)] ...) grouped?]
              @defproc[(agg [g grouped?] [agg-expr any/c] ...) dataframe?]
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
                             [#:seed seed (or/c exact-nonnegative-integer? #f) #f])
                       Expr-ptr?]
              @defproc[(gather [x (or/c Expr-ptr? string?)]
                               [indices (or/c Expr-ptr? series? (listof exact-integer?))])
                       Expr-ptr?])]{
  Ordering within a column (@tt{.rank}, @tt{.gather}); @racket[sort-by] is
  documented with the other sorts. @racket[rank] numbers each
  value by its place in the sorted order, ties resolved by
  @racket[#:method]; the result is @racket['uint32], or @racket['float64]
  for @racket['average]. @racket[gather] picks values by position. Each
  lifts a column name with @racket[col], and each is computed per group
  under @racket[over].

  @examples[#:eval ev
(define scores (dataframe (list (series '("a" "b" "c" "d") #:name "name")
                                (series '(30 10 30 20) #:name "score"))))
(~> scores
    (with-columns (~> (col "score") (rank #:method 'dense #:descending #t) (alias "dense"))
                  (~> (col "score") (rank #:method 'ordinal) (alias "ordinal"))))
(~> scores (select (gather "name" '(3 0))))
(eval:error (rank "score" #:method 'first))]}

@deftogether[(@defproc[(sum [v any/c] ...) any/c]
              @defproc[(mean [v any/c] ...) any/c]
              @defproc[(min [v any/c] ...) any/c]
              @defproc[(max [v any/c] ...) any/c])]{
  These dispatch on their argument. Applied to a single series, they reduce it
  (dispatching on its dtype): @racket[min], @racket[max] and @racket[sum]
  preserve the input dtype, while @racket[mean] always returns a
  @racket[float64], so the mean of an integer series is a flonum (see
  @secref["promotion"]). Applied to a single expression or a bare column-name
  string, they produce the corresponding aggregation expression — so
  @racket[(sum (col "value"))] reads like Polars' @tt{col("value").sum()} and is
  used inside @racket[agg] (see @secref["ref-fluent"]). Applied to anything else
  they fall back to the usual numeric behaviour, so @racket[(max 1 2 3)] still
  works.

  @examples[#:eval ev
(define s (series '(1 2 3 4) #:name "v"))
(list (sum s) (mean s) (min s) (max s))
(max 1 2 3)]}

@deftogether[(@defproc[(count    [x any/c]) any/c]
              @defproc[(n-unique [x any/c]) any/c]
              @defproc[(median   [x any/c]) any/c]
              @defproc[(std [x any/c] [#:ddof ddof exact-nonnegative-integer? 1]) any/c]
              @defproc[(var [x any/c] [#:ddof ddof exact-nonnegative-integer? 1]) any/c]
              @defproc[(alias [e any/c] [name string?]) any/c])]{
  Aggregation-expression builders for use inside @racket[agg], alongside the
  expression arms of @racket[sum], @racket[mean], @racket[min] and @racket[max].
  Each accepts an expression or a bare column-name string (lifted with
  @racket[col]), so @racket[(count "value")] and @racket[(count (col "value"))]
  are equivalent. @racket[alias] names a result, matching Polars' @tt{.alias}:
  @racket[(alias (sum (col "value")) "total")]. @racket[std] and @racket[var]
  take a @racket[#:ddof] degrees-of-freedom adjustment, defaulting to 1.}

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
                              [#:decimals decimals exact-nonnegative-integer? 0]) any/c])]{
  Element-wise power (@tt{**}) and rounding to @racket[#:decimals] places
  (@tt{.round}). Each takes an expression or a bare column-name string (lifted
  with @racket[col]); @racket[round] on a plain number falls back to numeric
  rounding. Ties round to even in both cases, as in Python Polars and
  @racketmodname[racket/base]. See @secref["fluent-shadowing"].

  @examples[#:eval ev
(~> (dataframe (list (series '(-2.5 -1.5 0.5 1.5 2.5) #:name "x")))
    (select (round "x")))
(round 2.5)]}

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
  lifted with @racket[lit], which has no date spelling; parse a string instead:
  @racket[(str->date (lit "1982-12-31"))]. A list @racket[rhs] holds integers,
  reals, strings, symbols (read as strings, as @racket[lit] reads them) or
  booleans, all of one kind.}

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

@deftogether[(@defproc[(str-extract [x (or/c Expr-ptr? string?)] [pattern string?]
                                    [#:group-index group-index exact-nonnegative-integer? 1])
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
                                      [#:strict strict boolean? #t]
                                      [#:exact exact boolean? #t]
                                      [#:cache cache boolean? #t])
                       Expr-ptr?])]{
  @racket[str-extract] returns capture group @racket[#:group-index] of the
  first regex match (@tt{.str.extract}). @racket[str->date] and
  @racket[str->datetime] parse strings with a chrono @tt{strptime}
  @racket[#:format], inferred when omitted (@tt{.str.to_date},
  @tt{.str.to_datetime}); @racket[#:strict #f] yields null instead of raising
  on unparseable values.}

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
                 [#:name name string? ""]
                 [#:dtype dtype (or/c #f symbol? pair?) #f])
         series?]{
  Builds a series from a list or vector. When @racket[#:dtype] is omitted the
  dtype is inferred from the elements; otherwise it is taken from
  @racket[dtype]. Both short spellings (@racket['i32], @racket['f64],
  @racket['str], @racket['bool]) and canonical symbols (@racket['int32],
  @racket['float64], @racket['string], @racket['boolean]) are accepted. Use
  @racket[polars-null] for missing values. Exact integers are coerced to
  flonums when the target dtype is floating point. Symbols infer
  @racket['categorical]; a @racket['categorical] or Enum (@racket[define-enum])
  series is built from strings or symbols alike, and an Enum raises on a
  value outside its categories (@secref["ref-categorical"]).

  @examples[#:eval ev
(series '(1 2 3) #:name "ints")
(series '(1.5 2.5) #:name "floats" #:dtype 'f32)
(series (list 1 polars-null 3) #:name "with-null")
(series '(IAH ATL IAH) #:name "dest")
(define-enum severity debug info error)
(series '("debug" "error") #:dtype severity)
(eval:error (series '(debug fatal) #:dtype severity))]}

@defproc[(series->string [s series?]) string?]{
  Renders @racket[s] in Polars' series format (a @tt{shape} line, a
  @tt{Series: 'name' [dtype]} line, then the bracketed values, truncated to the
  first and last five when longer than ten). This is also what a series prints
  as in the REPL.}

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
  (@racket['(datetime milliseconds #f)], @racket['(enum low mid high)],
  @racket['(decimal 10 2)]).
  @racket[len] returns the number of elements (and, on a dataframe, the number of
  rows). @racket[null-count] returns the number of null entries.}

@defproc[(series-name [s series?]) string?]{
  Returns the name of @racket[s], as Polars' @tt{Series.name}; a column taken
  from a dataframe is named after the column.

  @examples[#:eval ev #:label #f
(series-name (series '(1 2) #:name "ints"))]}

@deftogether[(@defproc[(rename [s series?] [new-name string?]) series?]
              @defproc[(rename! [s series?] [new-name string?]) void?]
              @defproc[(clone [s series?]) series?]
              @defproc[(series-clone [s series?]) series?])]{
  @racket[rename!] renames a series in place (matching Polars), returning
  @racket[void] as is conventional for @litchar{!} mutators; @racket[rename]
  returns a renamed copy and leaves the original untouched. @racket[clone] (and
  its series-specific alias @racket[series-clone]) returns an independent copy.}

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
       (list @racket['(datetime unit tz)] @elem{a gregor @tt{datetime}, floored to the second})
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
(series->list (series (list (datetime 2024 1 2 3 4 5) polars-null)))
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
  duplicate category, or none, is a syntax error. The datum itself is
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

@deftogether[(@defproc[(series-new-i8   [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-i16  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-i32  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-i64  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-u8   [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-u16  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-u32  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-u64  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-f32  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-f64  [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-bool [name string?] [values list?]) Series-ptr?]
              @defproc[(series-new-str  [name string?] [values list?]) Series-ptr?])]{
  Build a series of the dtype named by the suffix from a list of values.
  @racket[polars-null] among the values produces a null entry. Unlike
  @racket[series], no coercion happens: the integer constructors want exact
  integers, the float constructors want flonums (an exact @racket[1] is
  rejected), @racket[series-new-bool] wants booleans and @racket[series-new-str]
  wants strings. Each constructor has a @tt{/vec} sibling
  (@racketid[series-new-i32/vec], @racketid[series-new-f64/vec], …) that takes a
  vector instead of a list.}

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
  @racket[mean] dispatch on the dtype for you and are the preferred surface.}

@defproc[(series-cast [s Series-ptr?] [dtype (or/c symbol? pair?)]) Series-ptr?]{
  Returns a copy of @racket[s] converted to @racket[dtype], given as a canonical
  dtype symbol (@racket['int8] through @racket['int64], @racket['uint8] through
  @racket['uint64], @racket['float32], @racket['float64], @racket['boolean],
  @racket['string], @racket['binary], @racket['date], @racket['time],
  @racket['datetime], @racket['duration], @racket['null],
  @racket['categorical]), as @racket['(enum cat ...)] with distinct symbols
  for the categories, or, for the two
  temporal dtypes with a time unit, as a list —
  @racket['(datetime milliseconds)], @racket['(duration nanoseconds)] — where
  the unit is one of @racket['nanoseconds], @racket['microseconds] or
  @racket['milliseconds]. Bare @racket['datetime] and @racket['duration]
  default to microseconds. Raises an error when Polars cannot perform the
  cast. The fluent @racket[cast] wraps this for the generic layer.}

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
  names.

  @examples[#:eval ev
(dataframe (list (series '("a" "b") #:name "k")
                 (series '(1 2) #:name "v")))]}

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
  dataframe. It is data-first, so it threads. @racket[#:rows] is reserved for
  row slicing and currently raises an error. Provided by the @racket[gen:has-ref]
  interface. For a whole column, @racket[series->list] and its siblings convert
  in one pass where a @racket[ref] loop makes one foreign call per element.}

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
  them. Quantiles use nearest interpolation. Every statistic of every column
  comes from one query, so Polars computes the columns in parallel.

  API gaps: a time-zone-aware datetime is written as its UTC clock time with no
  offset, where Python writes the local time and the offset; a binary column
  gets no @racket["min"] or @racket["max"].

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
  column when @racket[d] has none.

  @examples[#:eval ev
(define scores (dataframe (list (series '(10 25 18) #:name "score" #:dtype 'i32))))
(series-sum-i32 (dataframe-column scores "score"))
(eval:error (dataframe-column scores "points"))]}

@defproc[(DataFrame-ptr? [v any/c]) boolean?]{
  Recognises a foreign dataframe pointer. Both raw pointers returned by the
  low-level operations and @racket[dataframe] wrappers satisfy it.}

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

@deftogether[(@defproc[(dataframe-write-csv [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-write-parquet [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-parquet [path path-string?]) dataframe?]
              @defproc[(dataframe-write-json-lines [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-json-lines [path path-string?]) dataframe?])]{
  Round-trip a dataframe through CSV, Parquet, or newline-delimited JSON; the
  fluent @racket[read-csv] and friends are the surface. Like
  @racket[read-parquet], @racket[dataframe-read-parquet] accepts a glob
  pattern.}

@deftogether[(@defcsvproc[(dataframe-read-csv DataFrame-ptr?)]
              @defcsvproc[(lazyframe-scan-csv LazyFrame-ptr?)])]{
  The raw-pointer reader and scan under @racket[read-csv] and
  @racket[scan-csv], with the same keywords and checks.

  @examples[#:eval ev
(dataframe-height (dataframe-read-csv "flights.tsv" #:separator #\tab #:null-values "NA"))
(dataframe-height (lazyframe-collect (lazyframe-scan-csv "parts/*.csv")))]}

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

@deftogether[(@defproc[(dataframe-lazy [df DataFrame-ptr?]) LazyFrame-ptr?]
              @defproc[(lazyframe-collect [lf LazyFrame-ptr?]) DataFrame-ptr?])]{
  @racket[dataframe-lazy] starts a plan from an in-memory frame
  (@tt{df.lazy()}); @racket[lazyframe-collect] executes a plan and returns the
  resulting frame (@tt{lf.collect()}).}

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
                         [#:on on (or/c #f (listof string?)) #f]
                         [#:left-on left-on (or/c #f (listof string?)) #f]
                         [#:right-on right-on (or/c #f (listof string?)) #f]
                         [#:how how (or/c 'inner 'left 'outer 'full 'cross) 'inner])
         LazyFrame-ptr?]{
  Joins two plans. Give the key columns either as one list with @racket[#:on],
  when they have the same names on both sides, or as parallel
  @racket[#:left-on] and @racket[#:right-on] lists. @racket[#:how] selects the
  join kind; @racket['outer] and @racket['full] are synonyms, and a
  @racket['cross] join takes no keys. Omitting the keys for any other kind is
  an error. Collect the result with @racket[lazyframe-collect]:

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
              @defproc[(expr-std [e Expr-ptr?] [#:ddof ddof exact-nonnegative-integer? 1]) Expr-ptr?]
              @defproc[(expr-var [e Expr-ptr?] [#:ddof ddof exact-nonnegative-integer? 1]) Expr-ptr?])]{
  Aggregations. Each reduces the column @racket[e] evaluates to — over the
  whole frame in a @emph{select}, or per group inside @emph{group_by/agg}.
  @racket[expr-count] counts the non-null entries, as Polars' @tt{.count()}
  does. @racket[expr-std] and @racket[expr-var] take a @racket[#:ddof]
  degrees-of-freedom adjustment, defaulting to 1. The generic @racket[sum],
  @racket[mean], @racket[min], @racket[max], @racket[median], @racket[count],
  @racket[n-unique], @racket[first], @racket[last], @racket[std] and
  @racket[var] dispatch to these when given an expression or a column name.}

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
