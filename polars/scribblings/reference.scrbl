#lang scribble/manual
@require[@for-label[polars
                    (only-in threading ~> ~>>)
                    @; polars re-exports generic ops (min max sum sort filter comparisons,
                    @; arithmetic + - * /, logical and/or/not, reverse, when) that shadow racket/base
                    (except-in racket/base min max sort filter reverse and or not when + - * / > < >= <= = abs round floor sqrt exp log)]]

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
  @racket['datetime], @racket['duration], @racket['null]) or, for the two
  temporal dtypes with a time unit, as a list —
  @racket['(datetime milliseconds)], @racket['(duration nanoseconds)] — where
  the unit is one of @racket['nanoseconds], @racket['microseconds] or
  @racket['milliseconds]. Bare @racket['datetime] and @racket['duration]
  default to microseconds. Raises an error when Polars cannot perform the
  cast. The fluent @racket[cast] wraps this for the generic layer.}

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

@defproc[(describe [x (or/c series? dataframe?)]) dataframe?]{
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
  that statistic. Quantiles use nearest interpolation. Dispatches on
  @racket[series?] / @racket[dataframe?].}

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

@defproc[(DataFrame-ptr? [v any/c]) boolean?]{
  Recognises a foreign dataframe pointer. Both raw pointers returned by the
  low-level operations and @racket[dataframe] wrappers satisfy it.}

@defproc[(dataframe-vstack [top DataFrame-ptr?] [bottom DataFrame-ptr?]) DataFrame-ptr?]{
  Stacks the rows of @racket[bottom] beneath those of @racket[top], which must
  have the same columns in the same order, and returns the combined frame
  (Polars' @tt{vstack}). The fluent @racket[vstack] is the wrapper-returning
  equivalent.}

@subsection[#:tag "ref-reading-writing"]{Reading & writing}

@deftogether[(@defproc[(dataframe-write-csv [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-csv [path path-string?]) dataframe?]
              @defproc[(dataframe-write-parquet [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-parquet [path path-string?]) dataframe?]
              @defproc[(dataframe-write-json-lines [d dataframe?] [path path-string?]) void?]
              @defproc[(dataframe-read-json-lines [path path-string?]) dataframe?])]{
  Round-trip a dataframe through CSV, Parquet, or newline-delimited JSON.}

@section[#:tag "ref-expressions"]{Expressions}

An @deftech{expression} describes a column computation — a column reference, a
literal, or an operation over other expressions — without running it. The
same expression can be reused across the @emph{select}, @emph{with_columns},
@emph{filter} and @emph{group_by/agg} contexts, exactly as in Polars, and is
evaluated only when a context runs it against a frame. Expressions are foreign
values recognised by @racket[Expr-ptr?].

The bindings below are the monomorphic @tt{expr-*} layer. Most of them have a
generic counterpart in @secref["ref-fluent"] — @racket[expr-gt] underlies
@racket[>], @racket[expr-sum] underlies the expression arm of @racket[sum],
@racket[expr-alias] underlies @racket[alias] — and the generic spelling is the
preferred one; the @tt{expr-*} names are useful when a name would otherwise be
shadowed, or when you want to be explicit that an expression is being built.

@defproc[(Expr-ptr? [v any/c]) boolean?]{
  Returns @racket[#t] if @racket[v] is an @tech{expression}.}

@deftogether[(@defproc[(col [name string?]) Expr-ptr?]
              @defproc[(lit [v (or/c boolean? exact-integer? real? string?)]) Expr-ptr?]
              @defproc[(expr-alias [e Expr-ptr?] [name string?]) Expr-ptr?])]{
  The leaves. @racket[col] refers to the column called @racket[name]
  (@tt{pl.col}). @racket[lit] lifts a Racket scalar to a literal expression:
  booleans, exact integers (32-bit when they fit, 64-bit otherwise), other
  reals (as @racket['float64]) and strings. Every binary @tt{expr-*} operation
  applies @racket[lit] to a non-expression operand automatically, so it is
  rarely needed explicitly. @racket[expr-alias] names the column an expression
  produces, matching @tt{.alias}: @racket[(expr-alias (expr-sum (col "value")) "total")].}

@deftogether[(@defproc[(expr-add [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-sub [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-mul [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-div [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-mod [a any/c] [b any/c]) Expr-ptr?])]{
  Element-wise arithmetic. At least one operand is normally an expression;
  the other may be a scalar, which is lifted with @racket[lit], so
  @racket[(expr-mul (col "value") 2)] reads like @tt{col("value") * 2}. The
  generic @racket[+], @racket[-], @racket[*] and @racket[/] dispatch to these
  when given an expression.}

@deftogether[(@defproc[(expr-gt [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-lt [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-ge [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-le [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-eq [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-ne [a any/c] [b any/c]) Expr-ptr?])]{
  Element-wise comparisons producing a boolean expression; scalars are lifted
  with @racket[lit]. @racket[(expr-gt (col "value") 15)] is @tt{col("value") > 15}.
  The generic @racket[>], @racket[<], @racket[>=], @racket[<=], @racket[=] and
  @racket[!=] dispatch to these when given an expression.}

@deftogether[(@defproc[(expr-and [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-or  [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-xor [a any/c] [b any/c]) Expr-ptr?]
              @defproc[(expr-not [e Expr-ptr?]) Expr-ptr?])]{
  Element-wise boolean logic over boolean expressions, for combining
  predicates: @racket[(expr-and (expr-gt (col "value") 15) (expr-lt (col "cost") 3.0))].
  The generic @racket[and], @racket[or], @racket[xor] and @racket[not] dispatch
  to these when given an expression.}

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

@defproc[(sort [d dataframe?]
               [names (or/c string? (listof string?))]
               [#:descending descending (or/c boolean? (listof boolean?)) #f])
         dataframe?]{
  Sorts @racket[d] by one or more columns. @racket[#:descending] is a single
  boolean applied to all keys, or a per-key list. Applied to a non-dataframe it
  falls back to @racketmodname[racket/base]'s @racket[sort], so
  @racket[(sort '(3 1 2) <)] is @racket['(1 2 3)].}

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
  @tech{lazyframe} they extend the plan and return a lazyframe.}

@defproc[(cast [x (or/c Expr-ptr? series? string?)] [dtype (or/c symbol? pair?)])
         (or/c Expr-ptr? series?)]{
  Changes dtype. On an expression (or a column name, lifted with
  @racket[col]) it builds a cast expression, matching @tt{.cast}; on a series
  it converts eagerly and returns a series. @racket[dtype] takes the same
  spellings as @racket[series-cast].}

@defproc[(vstack [top dataframe?] [bottom dataframe?]) dataframe?]{
  Stacks the rows of @racket[bottom] beneath those of @racket[top], which must
  have the same columns in the same order (Polars' @tt{vstack}).}

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
  and belong inside @racket[select].}

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
  @tech{lazyframe}.}

@deftogether[(@defproc[(read-csv [path path-string?]) dataframe?]
              @defproc[(read-parquet [path path-string?]) dataframe?]
              @defproc[(read-ndjson [path path-string?]) dataframe?]
              @defproc[(write-csv [d dataframe?] [path path-string?]) void?]
              @defproc[(write-parquet [d dataframe?] [path path-string?]) void?]
              @defproc[(write-ndjson [d dataframe?] [path path-string?]) void?])]{
  Eager file I/O (@tt{pl.read_csv} / @tt{df.write_csv} and friends). Dates
  are not parsed on read; see @racket[str-to-date].}

@deftogether[(@defproc[(scan-csv [path path-string?]
                                 [#:has-header has-header boolean? #t]
                                 [#:separator separator char? #\,]
                                 [#:skip-rows skip-rows exact-nonnegative-integer? 0]
                                 [#:n-rows n-rows (or/c exact-nonnegative-integer? #f) #f])
                       lazyframe?]
              @defproc[(scan-parquet [path path-string?]
                                     [#:n-rows n-rows (or/c exact-nonnegative-integer? #f) #f])
                       lazyframe?])]{
  Start a @tech{lazyframe} plan from a file without reading it
  (@tt{pl.scan_csv} / @tt{pl.scan_parquet}); @racket[collect] runs it.}

@deftogether[(@defproc[(lazy [d dataframe?]) lazyframe?]
              @defproc[(collect [lf lazyframe?]) dataframe?])]{
  @racket[lazy] turns a dataframe into a @tech{lazyframe} — a plan that
  @racket[select], @racket[with-columns], @racket[filter] and the other
  fluent operations extend without running anything — and @racket[collect]
  executes the plan and returns the resulting dataframe.}

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

@deftogether[(@defproc[(pow [x (or/c Expr-ptr? string?)] [exponent (or/c Expr-ptr? real?)]) Expr-ptr?]
              @defproc[(round [x (or/c Expr-ptr? string? number?)]
                              [#:decimals decimals exact-nonnegative-integer? 0]) any/c])]{
  Element-wise power (@tt{**}) and rounding to @racket[#:decimals] places
  (@tt{.round}). Each takes an expression or a bare column-name string (lifted
  with @racket[col]); @racket[round] on a plain number falls back to numeric
  rounding. See @secref["fluent-shadowing"].}

@deftogether[(@defproc[(is-between [x (or/c Expr-ptr? string?)] [lower any/c] [upper any/c]
                                   [#:closed closed (or/c 'both 'left 'right 'none) 'both])
                       Expr-ptr?]
              @defproc[(is-in [x (or/c Expr-ptr? string?)] [rhs (or/c list? series? Expr-ptr?)])
                       Expr-ptr?])]{
  Range and membership predicates (@tt{.is_between}, @tt{.is_in}). Bounds are
  lifted with @racket[lit], which has no date spelling; cast a string instead:
  @racket[(cast (lit "1982-12-31") 'date)].}

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
              @defproc[(str-to-date [x (or/c Expr-ptr? string?)]
                                    [#:format format (or/c string? #f) #f]
                                    [#:strict strict boolean? #t]
                                    [#:exact exact boolean? #t]
                                    [#:cache cache boolean? #t])
                       Expr-ptr?]
              @defproc[(str-to-datetime [x (or/c Expr-ptr? string?)]
                                        [#:format format (or/c string? #f) #f]
                                        [#:unit unit (or/c 'milliseconds 'microseconds 'nanoseconds) 'microseconds]
                                        [#:strict strict boolean? #t]
                                        [#:exact exact boolean? #t]
                                        [#:cache cache boolean? #t])
                       Expr-ptr?])]{
  @racket[str-extract] returns capture group @racket[#:group-index] of the
  first regex match (@tt{.str.extract}). @racket[str-to-date] and
  @racket[str-to-datetime] parse strings with a chrono @tt{strptime}
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

@section{Generic interfaces}

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
