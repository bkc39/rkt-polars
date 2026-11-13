#lang scribble/manual
@(require "utils.rkt")

@title{Polars: Racket bindings to Polars}
@author{bkc}

@defmodule[polars]

@racketmodname[polars] provides Racket bindings to the
@hyperlink["https://pola.rs/"]{Polars} DataFrame library. The bindings call
into a native compatibility library (@tt{libcompat}) built from the Rust
@tt{polars} crate; prebuilt shared objects for Linux (x86-64) and macOS
(arm64) are installed with the package, so no Rust toolchain is required at
install time (see @secref["install"]).

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

@section[#:tag "install"]{Installation}

@commandline{raco pkg install polars}

installs @racketmodname[polars] and, as a dependency for the platform, the
native package that holds @tt{libcompat}: @tt{polars-x86_64-linux} on x86-64
Linux, @tt{polars-aarch64-linux} on arm64 Linux, @tt{polars-aarch64-macosx} on
arm64 macOS. When @racketmodname[polars]
is set up, @exec{raco setup} fails if the native package is not the version
this @racketmodname[polars] needs or its library is not the one the package
was built with; @exec{raco pkg update polars polars-x86_64-linux} (with the
platform's package) brings the two together. A native package installed or
updated on its own is not set up with @racketmodname[polars], so only its
version is checked, when @racket[(require polars)] loads it.

On a supported platform without the native package, the pre-installer
only warns and @racket[(require polars)] raises @racket[exn:fail], each
naming the package to install with @exec{raco pkg install}; on any other
platform both name the supported platforms instead. Building this manual
requires @racketmodname[polars], so @exec{raco setup} fails until the native
package is installed; @exec{raco pkg install --no-docs} installs
@racketmodname[polars] without it.

When @envvar{RKT_POLARS_COMPAT_LIB_PATH} is set and not empty,
@racketmodname[polars] loads the @tt{libcompat} in the @filepath{lib}
directory it names instead, unchecked.

@exec{raco exe} and @exec{raco distribute} are not supported yet: an
executable does not find the native package.

@include-section["guide.scrbl"]
@include-section["reference.scrbl"]

@section[#:tag "status"]{Status}

This is an early release; the API surface is still evolving. See the
@hyperlink["https://github.com/bkc39/rkt-polars"]{project repository} for
examples and the current set of supported operations.
