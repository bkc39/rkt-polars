#lang scribble/manual
@(require "utils.rkt")

@title[#:tag "guide"]{User guide}

A chapter-by-chapter port of the upstream
@hyperlink["https://docs.pola.rs/user-guide/"]{Polars user guide} to
@racketmodname[polars]. Every snippet has a runnable counterpart under
@tt{user-guide/<chapter>/} in the project repository, paired with the
equivalent Python program:

@verbatim|{
  racket user-guide/getting-started/expressions-and-contexts.rkt
  python user-guide/getting-started/expressions_and_contexts.py
}|

Snippets use the fluent, thread-first style: each verb takes the frame as its
first argument and @racket[~>] (re-provided by @racketmodname[polars]) chains
them. Where the bindings have no spelling for an upstream call, the chapter
says so and shows the nearest workaround. For the definition of every binding
mentioned, see the @secref["reference"].

@include-section["guide/getting-started.scrbl"]
@include-section["guide/concepts.scrbl"]
