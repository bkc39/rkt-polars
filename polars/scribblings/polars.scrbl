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

This manual has two parts. The @secref["guide"] is a guided, narrative tour
modelled on the upstream
@hyperlink["https://docs.pola.rs/user-guide/getting-started/"]{Polars
getting-started guide}; the @secref["reference"] documents the public API.

@local-table-of-contents[]

@include-section["guide.scrbl"]
@include-section["reference.scrbl"]

@section{Status}

This is an early release; the API surface is still evolving. See the
@hyperlink["https://github.com/bkc39/rkt-polars"]{project repository} for
examples and the current set of supported operations.
