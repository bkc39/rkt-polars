#lang scribble/manual
@require[@for-label[polars
                    @; polars re-exports generic min/max that shadow racket/base
                    (except-in racket/base min max)]]

@title{Polars: Racket bindings to Polars}
@author{bkc}

@defmodule[polars]

@racketmodname[polars] provides Racket bindings to the
@hyperlink["https://pola.rs/"]{Polars} DataFrame library. The bindings call
into a native compatibility library (@tt{libcompat}) built from the Rust
@tt{polars} crate; prebuilt shared objects for Linux (x86-64) and macOS
(arm64) ship with the package and are installed automatically, so no Rust
toolchain is required at install time.

The @racketmodname[polars] module re-exports three groups of operations:

@itemlist[
  @item{@bold{Series} --- typed, one-dimensional columns of data.}
  @item{@bold{Expressions} --- composable, lazily-evaluated column
        expressions used to describe transformations.}
  @item{@bold{DataFrames and LazyFrames} --- tabular data and the lazy query
        plans that produce it.}
]

Temporal values exchanged with Racket use
@hyperlink["https://docs.racket-lang.org/gregor/"]{gregor} dates and
datetimes.

@section{High-level (generic) API}

Alongside the monomorphic, dtype-suffixed bindings (@racket[series-new-i32],
@racket[series-sum-f64], and friends), @racketmodname[polars] provides a small
set of generic operations that dispatch at runtime on a series' dtype (read via
@racket[series-dtype]) or on whether a value is a series or a dataframe. A
series is a single opaque value that already carries its dtype, so these
generics need no wrapper struct.

@defproc[(series [elements (or/c list? vector?)]
                 [#:name name string? ""]
                 [#:dtype dtype (or/c #f symbol? pair?) #f])
         Series-ptr?]{
  Builds a series from a list or vector. When @racket[#:dtype] is omitted the
  dtype is inferred from the elements; otherwise it is taken from
  @racket[dtype]. Both short spellings (@racket['i32], @racket['f64],
  @racket['str], @racket['bool]) and canonical symbols (@racket['int32],
  @racket['float64], @racket['string], @racket['boolean]) are accepted. Use
  @racket[polars-null] for missing values. Exact integers are coerced to
  flonums when the target dtype is floating point.}

@deftogether[(@defproc[(sum [v any/c] ...) any/c]
              @defproc[(mean [v any/c] ...) any/c]
              @defproc[(min [v any/c] ...) any/c]
              @defproc[(max [v any/c] ...) any/c])]{
  Applied to a single series, these reduce it, dispatching on its dtype.
  Applied to anything else they fall back to the usual numeric behaviour, so
  @racket[(max 1 2 3)] still works. @racket[min], @racket[max] and @racket[sum]
  preserve the input dtype; @racket[mean] always returns a @racket[float64], so
  the mean of an integer series is a flonum. See @secref["promotion"].}

@defproc[(describe [x (or/c Series-ptr? DataFrame-ptr?)]) void?]{
  Prints a one-line summary (name, length, dtype, null count) for a series, or
  a shape and per-column dtype summary for a dataframe.}

@defproc[(ref [x (or/c Series-ptr? DataFrame-ptr?)]
              [key (or/c exact-nonnegative-integer? string?)]) any/c]{
  On a series, returns the element at the given index (like @racket[series-ref]).
  On a dataframe, returns the column named @racket[key], or the column at index
  @racket[key]. It is data-first, so it threads.}

@deftogether[(@defproc[(rename [s Series-ptr?] [new-name string?]) Series-ptr?]
              @defproc[(rename! [s Series-ptr?] [new-name string?]) void?]
              @defproc[(clone [s Series-ptr?]) Series-ptr?]
              @defproc[(series-clone [s Series-ptr?]) Series-ptr?])]{
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

@section{Getting started}

For a guided tour modelled on the upstream
@hyperlink["https://docs.pola.rs/user-guide/getting-started/"]{Polars
getting-started guide}, see
@other-doc['(lib "polars/scribblings/getting-started.scrbl")]. Runnable Racket
and Python versions of every snippet live under @tt{user-guide/getting-started/}
in the @hyperlink["https://github.com/bkc39/rkt-polars"]{project repository}.

@section{Status}

This is an early release; the API surface is still evolving. See the
@hyperlink["https://github.com/bkc39/rkt-polars"]{project repository} for
examples and the current set of supported operations.
