#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         (only-in racket/contract flat-contract-with-explanation raise-blame-error)
         (only-in racket/contract/base [-> ->/c] ->* and/c contract-name contract-out listof or/c)
         (only-in racket/list filter-not index-of)
         (only-in racket/match match)
         (only-in polars/private/c-integer int64/c size/c uint64/c uint8/c)
         (only-in polars/private/expr-core ->expr/who Expr-ptr? _Expr-ptr _Expr-ptr/null col
                  define-compat expr-drop sort-by/c)
         (only-in polars/private/foreign
                  Series-ptr? _Series-ptr polars-null? series-new-bool series-new-f64
                  series-new-i64 series-new-null series-new-str series-new-u64 sort-flags)
         (only-in polars/private/series series-new-temporal)
         (only-in polars/private/temporal temporal-value-dtype temporal-values-dtype zone-conflict))

(provide expr-lit-series expr-is-between
         expr-is-unique expr-is-duplicated
         expr-is-first-distinct expr-is-last-distinct
         expr-reverse expr-filter
         index-list/c membership-list/c
         expr-sum expr-mean expr-min expr-max
         expr-count expr-n-unique expr-first expr-last expr-median
         expr-over
         expr-when
         rank-method/c
         ->key-expr
         (contract-out
          [expr-rank (->* (Expr-ptr?)
                          (#:method rank-method/c #:descending boolean? #:seed (or/c #f uint64/c))
                          Expr-ptr?)]
          [expr-head (->* (Expr-ptr?) (#:n (or/c #f size/c)) Expr-ptr?)]
          [expr-tail (->* (Expr-ptr?) (#:n (or/c #f size/c)) Expr-ptr?)]
          [expr-slice (->/c Expr-ptr? int64/c size/c Expr-ptr?)]
          [expr-is-in (->* (Expr-ptr? (and/c (or/c Expr-ptr? Series-ptr? list?) membership-list/c))
                           (#:who symbol?)
                           Expr-ptr?)]
          [expr-gather (->/c Expr-ptr? (or/c Expr-ptr? Series-ptr? index-list/c) Expr-ptr?)]
          [expr-std (->* (Expr-ptr?) (#:ddof uint8/c) Expr-ptr?)]
          [expr-var (->* (Expr-ptr?) (#:ddof uint8/c) Expr-ptr?)]
          [expr-sort (->* (Expr-ptr?) (#:descending boolean? #:nulls-last boolean?) Expr-ptr?)]
          [expr-sort-by (sort-by/c Expr-ptr? 'expr-sort-by/c)]))


(define-compat expr-lit-series
  (_fun _Series-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-is-unique
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-is-duplicated
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-is-first-distinct
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))
(define-compat expr-is-last-distinct
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))

(define-compat expr-is-in/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_is_in
  #:wrap (allocator expr-drop))

(define (->membership-expr who rhs)
  (cond
    [(Expr-ptr? rhs) rhs]
    [(Series-ptr? rhs) (expr-lit-series rhs)]
    [else
     (define vals (filter-not polars-null? rhs))
     (define s
       (cond
         [(null? vals) (series-new-null "" (length rhs))]
         [(andmap int64/c vals) (series-new-i64 "" rhs)]
         [(andmap uint64/c vals) (series-new-u64 "" rhs)]
         [(andmap real? vals) (series-new-f64 "" (map-non-null exact->inexact rhs))]
         [(andmap string? vals) (series-new-str "" rhs)]
         [(andmap symbol? vals) (series-new-str "" (map-non-null symbol->string rhs))]
         [(andmap boolean? vals) (series-new-bool "" rhs)]
         [(temporal-values-dtype vals)
          => (lambda (dtype)
               (check-one-zone who vals)
               (series-new-temporal who "" rhs dtype))]
         [else (error who "is-in list must be homogeneous ints/reals/strings/symbols/booleans/gregor values, got ~v" rhs)]))
     (expr-lit-series s)]))

(define (integer-and-float vals)
  (for/fold ([integer #f] [float #f] #:result (and integer float (list integer float)))
            ([v (in-list vals)])
    (values (or integer (and (exact-integer? v) v))
            (or float (and (real? v) (not (exact-integer? v)) v)))))

(define membership-integers/c (or/c (listof int64/c) (listof uint64/c)))

(define (membership-explanation v)
  (define vals (if (list? v) (filter-not polars-null? v) '()))
  (match (integer-and-float vals)
    [(list integer float)
     (lambda (blame)
       (raise-blame-error blame v
                          (string-append "the list mixes integers and floats, which have no"
                                         " common dtype\n  integer: ~e\n  float: ~e\n  given: ~e")
                          integer float v))]
    [_ #:when (and (andmap exact-integer? vals)
                   (not (or (andmap int64/c vals) (andmap uint64/c vals))))
     (lambda (blame)
       (raise-blame-error blame v '(expected: "~s" given: "~e")
                          (contract-name membership-integers/c) v))]
    [_ #t]))

(define membership-list/c
  (flat-contract-with-explanation membership-explanation #:name 'membership-list/c))

(define index-list/c (listof (or/c int64/c polars-null?)))

(define (map-non-null f xs)
  (for/list ([x (in-list xs)])
    (if (polars-null? x) x (f x))))

(define (check-one-zone who vals)
  (define conflict (zone-conflict vals))
  (when conflict
    (raise-arguments-error who "the values have no common dtype: their time zones differ"
                           "dtype" (temporal-value-dtype (car conflict))
                           "other dtype" (temporal-value-dtype (cadr conflict)))))

(define (expr-is-in e rhs #:who [who 'expr-is-in])
  (expr-is-in/raw e (->membership-expr who rhs)))

(define-compat expr-is-between/raw
  (_fun _Expr-ptr _Expr-ptr _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_is_between
  #:wrap (allocator expr-drop))

(define (closed->byte who closed)
  (case closed
    [(both) 0] [(left) 1] [(right) 2] [(none) 3]
    [else (error who "closed must be one of 'both 'left 'right 'none, got ~v" closed)]))

(define (expr-is-between e lower upper #:closed [closed 'both])
  (expr-is-between/raw e (->expr/who 'expr-is-between lower) (->expr/who 'expr-is-between upper)
                       (closed->byte 'expr-is-between closed)))

(define-compat expr-reverse
  (_fun _Expr-ptr -> _Expr-ptr) #:wrap (allocator expr-drop))

(define-compat expr-filter/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_filter
  #:wrap (allocator expr-drop))

(define (expr-filter e predicate) (expr-filter/raw e (->expr/who 'expr-filter predicate)))

(define-compat expr-gather/raw
  (_fun _Expr-ptr _Expr-ptr -> _Expr-ptr)
  #:c-id expr_gather
  #:wrap (allocator expr-drop))

(define (expr-gather e indices)
  (expr-gather/raw e (->index-expr indices)))

(define (->index-expr indices)
  (cond
    [(Expr-ptr? indices) indices]
    [(Series-ptr? indices) (expr-lit-series indices)]
    [else (expr-lit-series (series-new-i64 "" indices))]))

(define-compat expr-sort-by/raw
  (_fun _Expr-ptr
        (by : (_list i _Expr-ptr))
        (descending : (_list i _stdbool))
        (nulls-last : (_list i _stdbool))
        (_size = (length by))
        (maintain-order : _stdbool)
        -> _Expr-ptr/null)
  #:c-id expr_sort_by_with_options
  #:wrap (allocator expr-drop))

(define (expr-sort-by e #:by by
                      #:descending [descending #f]
                      #:nulls-last [nulls-last #f]
                      #:maintain-order [maintain-order #f])
  (define by-list (if (list? by) by (list by)))
  (or (expr-sort-by/raw e (map ->key-expr by-list)
                        (sort-flags 'expr-sort-by "#:descending" descending by-list)
                        (sort-flags 'expr-sort-by "#:nulls-last" nulls-last by-list)
                        maintain-order)
      (error 'expr-sort-by "failed to build the sort_by expression")))

(define-compat expr-rank/raw
  (_fun _Expr-ptr _uint8 _uint8 _uint8 _uint64 -> _Expr-ptr)
  #:c-id expr_rank
  #:wrap (allocator expr-drop))

(define rank-methods '(average min max dense ordinal))

(define rank-method/c (apply or/c rank-methods))

(define (expr-rank e #:method [method 'average] #:descending [descending #f] #:seed [seed #f])
  (expr-rank/raw e
                 (index-of rank-methods method)
                 (if descending 1 0)
                 (if seed 1 0)
                 (or seed 0)))

(define-compat expr-head/raw
  (_fun _Expr-ptr _uint8 _size -> _Expr-ptr)
  #:c-id expr_head
  #:wrap (allocator expr-drop))

(define-compat expr-tail/raw
  (_fun _Expr-ptr _uint8 _size -> _Expr-ptr)
  #:c-id expr_tail
  #:wrap (allocator expr-drop))

(define (expr-head e #:n [n 10])
  (expr-head/raw e (if n 1 0) (or n 0)))

(define (expr-tail e #:n [n 10])
  (expr-tail/raw e (if n 1 0) (or n 0)))

(define-compat expr-slice
  (_fun _Expr-ptr _int64 _size -> _Expr-ptr)
  #:c-id expr_slice_v2
  #:wrap (allocator expr-drop))

(define-compat expr-sum
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-mean
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-min
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-max
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-count
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-n-unique
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-first
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-last
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-median
  (_fun _Expr-ptr -> _Expr-ptr)
  #:wrap (allocator expr-drop))

(define-compat expr-std/raw
  (_fun _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_std
  #:wrap (allocator expr-drop))

(define-compat expr-var/raw
  (_fun _Expr-ptr _uint8 -> _Expr-ptr)
  #:c-id expr_var
  #:wrap (allocator expr-drop))

(define (expr-std e #:ddof [ddof 1]) (expr-std/raw e ddof))
(define (expr-var e #:ddof [ddof 1]) (expr-var/raw e ddof))

(define-compat expr-over/c
  (_fun _Expr-ptr
        (parts : (_list i _Expr-ptr))
        (_size = (length parts))
        -> _Expr-ptr)
  #:c-id expr_over
  #:wrap (allocator expr-drop))

(define (expr-over e parts)
  (expr-over/c e (map ->key-expr parts)))

(define-compat expr-sort/raw
  (_fun _Expr-ptr _stdbool _stdbool -> _Expr-ptr/null)
  #:c-id expr_sort_with_options
  #:wrap (allocator expr-drop))

(define (expr-sort e #:descending [descending #f] #:nulls-last [nulls-last #f])
  (or (expr-sort/raw e descending nulls-last)
      (error 'expr-sort "failed to build the sort expression")))

(define-compat expr-when-then/c
  (_fun (conds : (_list i _Expr-ptr))
        (vals : (_list i _Expr-ptr))
        (_size = (length conds))
        (otherwise : _Expr-ptr)
        -> _Expr-ptr)
  #:c-id expr_when_then
  #:wrap (allocator expr-drop))

(define (expr-when clauses #:otherwise otherwise)
  (when (null? clauses)
    (error 'expr-when "requires at least one [pred value] clause"))
  (for ([c (in-list clauses)])
    (unless (and (list? c) (= 2 (length c)))
      (error 'expr-when "each clause must be (list pred value); got ~v" c)))
  (expr-when-then/c (for/list ([c (in-list clauses)]) (->expr/who 'expr-when (car c)))
                    (for/list ([c (in-list clauses)]) (->expr/who 'expr-when (cadr c)))
                    (->expr/who 'expr-when otherwise)))

(define (->key-expr v)
  (cond
    [(Expr-ptr? v) v]
    [(string? v) (col v)]
    [else (error '->key-expr "expected string or Expr-ptr, got ~v" v)]))

(module+ internal
  (provide expr-head expr-rank expr-slice expr-sort expr-sort-by expr-std expr-tail expr-var
           rank-methods))
