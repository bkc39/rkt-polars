#lang scribble/manual
@require[@for-label[polars
                    @; polars re-exports generic min/max that shadow racket/base
                    (except-in racket/base min max)]]

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
  Applied to a single series, these reduce it, dispatching on its dtype.
  Applied to anything else they fall back to the usual numeric behaviour, so
  @racket[(max 1 2 3)] still works. @racket[min], @racket[max] and @racket[sum]
  preserve the input dtype; @racket[mean] always returns a @racket[float64], so
  the mean of an integer series is a flonum. See @secref["promotion"].}

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

@defproc[(describe [x describable?]) void?]{
  Prints a one-line summary (name, length, dtype, null count) for a series, or
  a shape and per-column dtype summary for a dataframe. Provided by the
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
