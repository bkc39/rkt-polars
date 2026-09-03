#lang scribble/manual
@require[@for-label[polars
                    (only-in threading ~> ~>>)
                    @; polars re-exports generic ops (min max sum sort filter comparisons,
                    @; arithmetic + - * /, logical and/or/not, reverse, when) that shadow racket/base
                    (except-in racket/base min max sort filter reverse and or not when + - * / > < >= <= = abs round floor sqrt exp log)]]

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
