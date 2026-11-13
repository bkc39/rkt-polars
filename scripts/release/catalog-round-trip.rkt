#lang racket/base

(require (only-in polars ~>)
         (prefix-in pl: (only-in polars col dataframe filter ref series series->list >)))

(provide filter-round-trip)

(define (filter-round-trip)
  (~> (pl:dataframe (list (pl:series '(1 2 3) #:name "v")))
      (pl:filter (pl:> (pl:col "v") 1))
      (pl:ref "v")
      pl:series->list))
