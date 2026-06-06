#lang racket/base

;; Data-first frame/series operations that thread with ~>: filter, sort, the
;; reshaping verbs (head/tail/slice/reverse/unique/drop-nulls), dataframe column
;; ops (select/drop/with-column), the group-by/agg handle, and clone/rename.

(require racket/match
         (prefix-in base: racket/base)
         (except-in racket/list drop)
         (only-in racket/list [drop list-drop])
         polars/private/foreign
         polars/private/expr
         polars/private/generic/core)

(provide (all-defined-out))

;; filter: (filter df predicate-expr) / (filter df mask-series) -> dataframe.
;; Falls back to racket/base filter, so (filter even? '(1 2 3 4)) still works.
(define (filter . args)
  (match args
    [(list (? dataframe? d) (? Expr-ptr? pred))
     (wrap-dataframe (dataframe-filter-expr d pred))]
    [(list (? dataframe? d) (? series? mask))
     (wrap-dataframe (dataframe-filter d mask))]
    [(list (? lazyframe? lf) (? Expr-ptr? pred))
     (wrap-lazyframe (lazyframe-filter lf pred))]
    [_ (apply base:filter args)]))

;; sort: (sort df names #:descending d) -> dataframe; (sort series #:descending d)
;; -> series; otherwise racket/base sort.  `names` may be one name or a list.
(define (sort x [second unset] #:descending [descending unset])
  (cond
    [(dataframe? x)
     (when (eq? second unset)
       (error 'sort "sorting a dataframe requires column name(s)"))
     (wrap-dataframe
      (dataframe-sort x (if (list? second) second (list second))
                      #:descending (if (eq? descending unset) #f descending)))]
    [(lazyframe? x)
     (when (eq? second unset)
       (error 'sort "sorting a lazyframe requires column name(s)"))
     (wrap-lazyframe
      (lazyframe-sort x (if (list? second) second (list second))
                      #:descending (if (eq? descending unset) #f descending)))]
    [(series? x)
     (wrap-series
      (series-sort x #:descending (if (eq? descending unset) #f descending)))]
    [(eq? second unset)
     (error 'sort "racket/base sort needs a less-than? procedure")]
    [else (base:sort x second)]))

;; --- reshaping verbs (series + dataframe) -----------------------------------
;; reverse is series-only with a racket/base list fallback (no dataframe-reverse).

(define (head x n)
  (cond [(series? x)    (wrap-series    (series-head x n))]
        [(dataframe? x) (wrap-dataframe (dataframe-head x n))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-head x n))]
        [else (error 'head "expected a series, dataframe, or lazyframe, got ~v" x)]))

(define (tail x n)
  (cond [(series? x)    (wrap-series    (series-tail x n))]
        [(dataframe? x) (wrap-dataframe (dataframe-tail x n))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-tail x n))]
        [else (error 'tail "expected a series, dataframe, or lazyframe, got ~v" x)]))

(define (slice x offset length)
  (cond [(series? x)    (wrap-series    (series-slice x offset length))]
        [(dataframe? x) (wrap-dataframe (dataframe-slice x offset length))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-slice x offset length))]
        [else (error 'slice "expected a series, dataframe, or lazyframe, got ~v" x)]))

(define (unique x)
  (cond [(series? x)    (wrap-series    (series-unique x))]
        [(dataframe? x) (wrap-dataframe (dataframe-unique x))]
        [else (error 'unique "expected a series or dataframe, got ~v" x)]))

(define (drop-nulls x)
  (cond [(series? x)    (wrap-series    (series-drop-nulls x))]
        [(dataframe? x) (wrap-dataframe (dataframe-drop-nulls x))]
        [else (error 'drop-nulls "expected a series or dataframe, got ~v" x)]))

(define (reverse x)
  (cond [(series? x) (wrap-series (series-reverse x))]
        [(list? x)   (base:reverse x)]
        [else (error 'reverse "expected a series or list, got ~v" x)]))

;; --- dataframe column operations --------------------------------------------

;; Coerce select/with-columns specs into a flat Expr list: an Expr passes
;; through, a string/index is lifted via (col ...), a list splices.
(define (specs->exprs who d specs)
  (define (spec->expr s)
    (cond [(Expr-ptr? s) s]
          [(string? s) (col s)]
          [(exact-nonnegative-integer? s) (col (dataframe-column-name d s))]
          [else (error who "expected a column name, index, or Expr, got ~v" s)]))
  (append-map (lambda (s) (if (list? s) (map spec->expr s) (list (spec->expr s)))) specs))

;; select: project / derive columns -> dataframe (Polars df.select).  Variadic
;; and expression-aware: each argument is a column name, index, an Expr, or a
;; list thereof.  Always a dataframe.
(define (select d . specs)
  (guard-dataframe 'select d)
  (wrap-dataframe (dataframe-select-exprs d (specs->exprs 'select d specs))))

;; with-columns: add/replace columns in one pass (Polars df.with_columns).
;; Same variadic, expression-aware specs as select, but keeps the existing
;; columns and appends the (typically aliased) derived ones.
(define (with-columns d . specs)
  (guard-dataframe 'with-columns d)
  (wrap-dataframe (dataframe-with-columns d (specs->exprs 'with-columns d specs))))

;; drop: dataframe -> drop the named column(s); list -> racket/list drop.
(define (drop x arg)
  (cond
    [(dataframe? x)
     (wrap-dataframe (dataframe-drop-columns x (if (list? arg) arg (list arg))))]
    [(list? x) (list-drop x arg)]
    [else (error 'drop "expected a dataframe or list, got ~v" x)]))

;; with-column: attach a Series as a new column -> dataframe.
(define (with-column d s)
  (guard-dataframe 'with-column d)
  (wrap-dataframe (dataframe-with-column d s)))

;; join: left.join(right, ...) -> dataframe.  #:on (shared key) or
;; #:left-on/#:right-on; #:how 'inner/'left/'outer/'cross/'semi/'anti.
(define (join left right
              #:on [on #f] #:left-on [left-on #f] #:right-on [right-on #f]
              #:how [how 'inner])
  (cond
    [(dataframe? left)
     (wrap-dataframe
      (dataframe-join left right #:on on #:left-on left-on #:right-on right-on #:how how))]
    [(lazyframe? left)
     (wrap-lazyframe
      (lazyframe-join left right #:on on #:left-on left-on #:right-on right-on #:how how))]
    [else (error 'join "expected a dataframe or lazyframe, got ~v" left)]))

;; vstack: append the rows of another (compatible) dataframe -> dataframe.
(define (vstack a b)
  (guard-dataframe 'vstack a)
  (wrap-dataframe (dataframe-vstack a b)))

;; --- group-by / agg: the deferred, threading-compatible group handle --------
(struct grouped (frame keys) #:reflection-name 'grouped)

(define (group-by frame . keys)
  (when (null? keys)
    (error 'group-by "needs at least one group key"))
  (grouped frame keys))

(define (agg g . agg-exprs)
  (unless (grouped? g)
    (error 'agg "expected a grouped frame from group-by, got ~v" g))
  (define frame (grouped-frame g))
  (define keys (grouped-keys g))
  ;; dispatch on whether the grouped frame is eager or lazy
  (if (lazyframe? frame)
      (wrap-lazyframe (lazyframe-group-by-agg frame keys agg-exprs))
      (wrap-dataframe (dataframe-group-by-agg frame keys agg-exprs))))

;; --- lazy: a DataFrame's deferred query plan, and back ----------------------
;; (~> df lazy (filter ...) (group-by ...) (agg ...) (sort ...) collect) mirrors
;; df.lazy().filter(...)...collect().  filter / sort / group-by+agg above
;; dispatch on lazyframe? to build the plan instead of running eagerly.
(define (lazy d)
  (guard-dataframe 'lazy d)
  (wrap-lazyframe (dataframe-lazy d)))

(define (collect lf)
  (unless (lazyframe? lf)
    (error 'collect "expected a lazyframe, got ~v" lf))
  (wrap-dataframe (lazyframe-collect lf)))

;; --- clone / rename ---------------------------------------------------------
;; series-slice already returns a fresh series, so a full-length slice clones.
(define (series-clone s)
  (wrap-series (series-slice s 0 (series-len s))))

(define (clone x)
  (cond
    [(series? x) (series-clone x)]
    [else (error 'clone "expected a series, got ~v" x)]))

;; mutating: renames in place, returns void.
(define (rename! x new-name)
  (cond
    [(series? x) (series-rename x new-name)]
    [else (error 'rename! "expected a series, got ~v" x)]))

;; non-mutating: (rename series new-name) renames the series; (rename df old new)
;; renames a dataframe column.
(define (rename x a [b unset])
  (cond
    [(series? x)
     (define c (series-clone x))
     (series-rename c a)
     c]
    [(dataframe? x)
     (when (eq? b unset)
       (error 'rename "renaming a dataframe column needs old and new names"))
     (wrap-dataframe (dataframe-rename x a b))]
    [else (error 'rename "expected a series or dataframe, got ~v" x)]))

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/operators
           polars/private/generic/reductions
           polars/private/generic/test-fixtures)

  ;; clone / rename / rename!
  (define original (series '(1 2 3) #:name "orig" #:dtype 'i32))
  (define renamed (rename original "copy"))
  (check-pred series? renamed)
  (check-equal? (series-name original) "orig")
  (check-equal? (series-name renamed) "copy")
  (check-pred void? (rename! original "mutated"))
  (check-equal? (series-name original) "mutated")

  ;; filter: Expr predicate, mask series, racket/base fallback
  (define mask (> v64 15))
  (check-equal? (height (filter ops-df (> (col "value") 15))) 3)
  (check-equal? (height (filter ops-df mask)) 3)
  (check-equal? (filter even? '(1 2 3 4)) '(2 4))

  ;; sort: dataframe (multi-key) and racket/base fallback
  (define sorted (sort ops-df '("group" "value") #:descending '(#f #t)))
  (check-pred dataframe? sorted)
  (check-equal? (ref (ref sorted #:columns "value") 0) 25)
  (check-equal? (sort '(3 1 2) <) '(1 2 3))

  ;; group-by + agg
  (check-pred grouped? (group-by ops-df "group"))
  (define rolled
    (~> ops-df (group-by "group")
        (agg (alias (sum (col "value")) "sum_value")
             (alias (count (col "value")) "n"))))
  (check-pred dataframe? rolled)
  (check-equal? (height rolled) 3)
  (check-equal? (sort (column-names rolled) string<?) '("group" "n" "sum_value"))
  (define (group-sum g)
    (for/first ([i (in-range (height rolled))]
                #:when (string=? (ref (ref rolled #:columns "group") i) g))
      (ref (ref rolled #:columns "sum_value") i)))
  (check-equal? (group-sum "a") 35)
  (check-equal? (group-sum "b") 37)
  (check-equal? (group-sum "c") 18)

  ;; reshaping verbs (series + dataframe)
  (define (mask->list m) (for/list ([i (in-range (len m))]) (ref m i)))
  (check-equal? (mask->list (head v64 3)) '(10 25 7))
  (check-equal? (mask->list (tail v64 2)) '(30 18))
  (check-equal? (mask->list (slice v64 1 2)) '(25 7))
  (check-equal? (mask->list (reverse v64)) '(18 30 7 25 10))
  (check-equal? (min (head (sort v64) 1)) 7)
  (check-equal? (max (head (sort v64 #:descending #t) 1)) 30)
  (define dups (series '(1 1 2 3 3 3) #:dtype 'i32))
  (check-equal? (len (unique dups)) 3)
  (check-equal? (n-unique dups) 3)
  (define wn (series (list 1 polars-null 3) #:dtype 'i32))
  (check-equal? (len (drop-nulls wn)) 2)
  (check-equal? (reverse '(1 2 3)) '(3 2 1))
  (check-equal? (height (head ops-df 2)) 2)
  (check-equal? (height (tail ops-df 2)) 2)
  (check-equal? (height (slice ops-df 1 3)) 3)
  (check-equal? (height (drop-nulls ops-df)) 5)
  (check-equal? (height (unique ops-df)) 5)

  ;; dataframe column ops: select / drop / rename / with-column
  (check-equal? (column-names (select frame '("user" "cost"))) '("user" "cost"))
  (check-equal? (column-names (select frame "score")) '("score"))
  (define sel-expr (select frame (col "user") (alias (expr-add (col "score") 1) "score1")))
  (check-equal? (column-names sel-expr) '("user" "score1"))
  (check-equal? (ref (ref sel-expr #:columns "score1") 0) 11)
  (check-equal? (column-names (drop frame '("score"))) '("user" "cost"))
  (check-equal? (column-names (drop frame "cost")) '("user" "score"))
  (check-equal? (drop '(1 2 3 4) 2) '(3 4))
  (check-equal? (column-names (rename frame "score" "points")) '("user" "points" "cost"))
  (check-equal? (height (rename frame "score" "points")) 3)
  (define withcol (with-column frame (series '(10 20 30) #:name "bonus" #:dtype 'i32)))
  (check-equal? (column-names withcol) '("user" "score" "cost" "bonus"))
  (check-equal? (ref (ref withcol #:columns "bonus") 1) 20)
  ;; with-columns: derive columns from Exprs in one pass
  (let ([d (with-columns frame (alias (p+ (col "score") 1) "score1"))])
    (check-equal? (column-names d) '("user" "score" "cost" "score1"))
    (check-equal? (ref (ref d #:columns "score1") 0) 11))

  ;; --- operators inside filter / select / when-then (integration) -----------
  (check-equal? (height (filter ops-df (p-and (>= (col "value") 10) (<= (col "value") 25)))) 3)
  (check-equal? (height (filter ops-df (p-and (> (col "value") 15) (= (col "group") "a")))) 1)
  (check-equal? (height (filter ops-df (p-or (= (col "group") "a") (= (col "group") "c")))) 3)
  (check-equal? (height (filter ops-df (p-not (= (col "group") "a")))) 3)
  (let ([m (p-and (> v64 15) (< v64 20))])
    (check-equal? (height (filter ops-df m)) 1))
  (let ([d (select frame (alias (p+ (col "score") 1) "s1"))])
    (check-equal? (for/list ([i (in-range 3)]) (ref (ref d #:columns "s1") i)) '(11 26 19)))
  (let ([d (select frame (col "user")
                   (~> (p-when (> (col "score") 15)) (then 10) (otherwise 0) (alias "th")))])
    (check-equal? (column-names d) '("user" "th"))
    (check-equal? (for/list ([i (in-range 3)]) (ref (ref d #:columns "th") i)) '(0 10 10)))

  ;; --- join / vstack --------------------------------------------------------
  (define usr (dataframe (list (series '(1 2 3 4) #:name "uid" #:dtype 'i32)
                               (series '("alice" "bob" "carol" "dora") #:name "name"))))
  (define ord (dataframe (list (series '(1 2 2 5) #:name "uid" #:dtype 'i32)
                               (series '(10 20 30 40) #:name "amount" #:dtype 'i32))))
  (check-equal? (height (join usr ord #:on '("uid") #:how 'inner)) 3)   ; uid 1,2,2
  (check-equal? (height (join usr ord #:on '("uid") #:how 'left)) 5)    ; +uid 3,4 (null)
  (check-equal? (height (join (head usr 2) (head ord 2) #:how 'cross)) 4)
  (check-equal? (sort (column-names (join usr ord #:on '("uid") #:how 'inner)) string<?)
                '("amount" "name" "uid"))
  (define more (dataframe (list (series '(5 6) #:name "uid" #:dtype 'i32)
                                (series '("eve" "frank") #:name "name"))))
  (check-equal? (height (vstack usr more)) 6)
  (check-equal? (column-names (vstack usr more)) '("uid" "name"))

  ;; --- lazy pipeline: lazy -> filter -> group-by/agg -> sort -> collect ------
  (check-pred lazyframe? (lazy ops-df))
  (define ranked
    (~> ops-df lazy
        (filter (> (col "value") 8))          ; drops value 7 (group b's 7)
        (group-by "group")
        (agg (~> (col "value") sum (alias "sum_value")))
        (sort "sum_value" #:descending #t)
        collect))
  (check-pred dataframe? ranked)
  (check-equal? (height ranked) 3)
  (check-equal? (sort (column-names ranked) string<?) '("group" "sum_value"))
  (check-equal? (ref (ref ranked #:columns "group") 0) "a")    ; a: 10+25 = 35 (highest)
  (check-equal? (ref (ref ranked #:columns "sum_value") 0) 35)
  ;; lazy head / tail / slice (build the plan, then collect)
  (check-equal? (height (~> ops-df lazy (head 2) collect)) 2)
  (check-equal? (height (~> ops-df lazy (tail 2) collect)) 2)
  (check-equal? (height (~> ops-df lazy (slice 1 3) collect)) 3)
  ;; lazy join (both sides lazy)
  (check-equal? (height (~> usr lazy (join (lazy ord) #:on '("uid") #:how 'inner) collect)) 3))
