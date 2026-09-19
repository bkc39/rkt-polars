#lang scribble/manual
@(require "utils.rkt")

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

This manual has two parts: the @secref["guide"] works through the library by
example, and the @secref["reference"] documents the public API.

@bold{Acknowledgements.} This library and its documentation owe a great deal
to the @hyperlink["https://pola.rs/"]{Polars} project --- the Rust crate the
bindings call into, and the user guide and API documentation that shaped this
manual --- and to the Racket libraries it builds on, in particular
@hyperlink["https://docs.racket-lang.org/gregor/"]{gregor} for temporal values
and @hyperlink["https://docs.racket-lang.org/threading/"]{threading} for
@racket[~>]. We are grateful for all of them.

@local-table-of-contents[]

@include-section["guide.scrbl"]
@include-section["reference.scrbl"]

@section[#:tag "status"]{Status}

This is an early release; the API surface is still evolving. See the
@hyperlink["https://github.com/bkc39/rkt-polars"]{project repository} for
examples and the current set of supported operations.
