#lang scribble/manual
@require[@for-label[polars
                    (only-in threading ~> ~>>)
                    @; polars re-exports generic ops (min max sum sort filter comparisons,
                    @; logical and/or/not, reverse) that shadow racket/base
                    (except-in racket/base min max sort filter reverse and or not > < >= <= =)]]

@title[#:tag "reference"]{Reference}

Alongside the monomorphic, dtype-suffixed bindings (@racket[series-new-i32],
@racket[series-sum-f64], and friends), @racketmodname[polars] provides a small,
"rackety" high-level layer: @tech{series} and @tech{dataframe} wrapper values
reached through a handful of purpose-named generic operations. The generics
dispatch at runtime on the wrapper's type, or — for the reductions — on the
series' dtype (read via @racket[dtype]).

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
  flonums when the target dtype is floating point.}

@defproc[(series->string [s series?]) string?]{
  Renders @racket[s] in Polars' series format (a @tt{shape} line, a
  @tt{Series: 'name' [dtype]} line, then the bracketed values, truncated to the
  first and last five when longer than ten). This is also what a series prints
  as in the REPL.}

@deftogether[(@defthing[polars-null any/c]
              @defproc[(polars-null? [v any/c]) boolean?])]{
  @racket[polars-null] is the sentinel marking a missing value: pass it among the
  elements given to @racket[series] to produce nulls, and it is what @racket[ref]
  returns for a null entry. @racket[polars-null?] tests for it.}

@deftogether[(@defproc[(dtype [s has-dtype?]) (or/c symbol? pair?)]
              @defproc[(len [x sized?]) exact-nonnegative-integer?]
              @defproc[(null-count [s has-null-count?]) exact-nonnegative-integer?])]{
  Generic series accessors. @racket[dtype] returns the canonical dtype symbol
  (e.g. @racket['int32], @racket['float64], @racket['(datetime milliseconds #f)]).
  @racket[len] returns the number of elements (and, on a dataframe, the number of
  rows). @racket[null-count] returns the number of null entries.}

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
  works.}

@deftogether[(@defproc[(rename [s series?] [new-name string?]) series?]
              @defproc[(rename! [s series?] [new-name string?]) void?]
              @defproc[(clone [s series?]) series?]
              @defproc[(series-clone [s series?]) series?])]{
  @racket[rename!] renames a series in place (matching Polars), returning
  @racket[void] as is conventional for @litchar{!} mutators; @racket[rename]
  returns a renamed copy and leaves the original untouched. @racket[clone] (and
  its series-specific alias @racket[series-clone]) returns an independent copy.}

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
  names.}

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
  interface.}

@defproc[(describe [x describable?]) dataframe?]{
  Mirrors Polars' @tt{.describe()}: returns a summary-statistics @tech{dataframe}
  (which prints as a table). For a series the result has a @racket["statistic"]
  column and a @racket["value"] column, with rows adapted to the dtype — a
  numeric series gets @racket["count"], @racket["null_count"], @racket["mean"],
  @racket["std"], @racket["min"], @racket["25%"], @racket["50%"], @racket["75%"]
  and @racket["max"]; a boolean series drops @racket["std"] and the quantiles;
  other dtypes (string, temporal) keep just @racket["count"], @racket["null_count"],
  @racket["min"] and @racket["max"]. For a dataframe the result uses Polars'
  fixed nine-row layout (a @racket["statistic"] column plus one column per input
  column), leaving a cell @racket[polars-null] where a column has no value for
  that statistic. Quantiles use nearest interpolation. Provided by the
  @racket[gen:describable] interface.}

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
  @racket[display].}

@subsection[#:tag "ref-reading-writing"]{Reading & writing}

@deftogether[(@defproc[(dataframe-write-csv [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-csv [path path-string?]) dataframe?]
              @defproc[(dataframe-write-parquet [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-parquet [path path-string?]) dataframe?]
              @defproc[(dataframe-write-json-lines [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-json-lines [path path-string?]) dataframe?])]{
  Round-trip a dataframe through CSV, Parquet, or newline-delimited JSON.}

@section[#:tag "ref-fluent"]{Fluent pipelines}

A data-first layer that mirrors Polars' Python method chaining. Because each
operation takes the frame as its first argument, a pipeline reads as a
thread-first @racket[~>] chain (re-provided from @racketmodname[threading], so
@racket[(require polars)] is enough):

@racketblock[
(~> df
    (filter (> (col "value") 15))
    (group-by "group")
    (agg (alias (sum (col "value")) "sum_value")))
]

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

@defproc[(filter [d dataframe?] [predicate any/c]) dataframe?]{
  Keeps the rows of @racket[d] matching @racket[predicate], which may be a
  boolean expression — @racket[(filter df (> (col "value") 15))] — or a
  precomputed boolean-mask series. Returns a new dataframe. Applied to a
  non-dataframe it falls back to @racketmodname[racket/base]'s @racket[filter],
  so @racket[(filter even? '(1 2 3 4))] is @racket['(2 4)].}

@defproc[(sort [d dataframe?]
               [names (or/c string? (listof string?))]
               [#:descending descending (or/c boolean? (listof boolean?)) #f])
         dataframe?]{
  Sorts @racket[d] by one or more columns. @racket[#:descending] is a single
  boolean applied to all keys, or a per-key list. Applied to a non-dataframe it
  falls back to @racketmodname[racket/base]'s @racket[sort], so
  @racket[(sort '(3 1 2) <)] is @racket['(1 2 3)].}

@deftogether[(@defproc[(group-by [d dataframe?] [key (or/c string? any/c)] ...) grouped?]
              @defproc[(agg [g grouped?] [agg-expr any/c] ...) dataframe?]
              @defproc[(grouped? [v any/c]) boolean?])]{
  @racket[group-by] captures @racket[d] and one or more group keys in a deferred
  @racket[grouped] handle — no work happens yet — so it threads cleanly.
  @racket[agg] consumes the handle, computing the aggregation expressions per
  group in a single pass, and returns a dataframe with one row per group. The
  split mirrors @tt{df.group_by("g").agg(...)}; the row order of the result is
  not guaranteed.}

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

@section{Generic interfaces}

The high-level operations are small, purpose-named
@racketmodname[racket/generic] interfaces. A wrapper implements the interface
for each capability it has — a series and a dataframe both have a @racket[len]
and a @racket[shape], so both implement @racket[gen:sized] and
@racket[gen:has-shape]; only a series has a @racket[dtype]. Each interface
exports its method(s) and a predicate that recognises values implementing it.

@deftogether[(@defidform[gen:describable]
              @defproc[(describable? [v any/c]) boolean?])]{
  The @racket[describe] capability (method: @racket[describe]). Implemented by
  series and dataframes.}

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
