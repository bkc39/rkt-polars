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
Linux, @tt{polars-aarch64-macosx} on arm64 macOS. Its version must equal the
native version this @racketmodname[polars] names, and its library must have
the sha256 its @filepath{manifest.json} gives, or @exec{raco setup} fails;
@exec{raco pkg update polars polars-x86_64-linux} (with the platform's
package) brings the two together.

@racketmodname[polars] loads @tt{libcompat} from the first of:

@itemlist[#:style 'ordered
  @item{the @filepath{lib} directory that @envvar{RKT_POLARS_COMPAT_LIB_PATH}
        names, when it is set and not empty;}
  @item{a copy in @racketmodname[polars]'s @filepath{native-libs} directory,
        as a development build stages it, unless a native package is installed
        and the copy is not that build's;}
  @item{the native package.}
]

On any other platform, or without the native package, @racket[(require polars)]
raises @racket[exn:fail], naming the platforms or the package to install and
@envvar{RKT_POLARS_COMPAT_LIB_PATH}.

@include-section["guide.scrbl"]
@include-section["reference.scrbl"]

@section[#:tag "status"]{Status}

This is an early release; the API surface is still evolving. See the
@hyperlink["https://github.com/bkc39/rkt-polars"]{project repository} for
examples and the current set of supported operations.
