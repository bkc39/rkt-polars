#lang racket/base

(require racket/match
         (only-in racket/contract/base
                  -> ->* ->i any/c contract-out flat-contract-predicate integer-in listof or/c
                  unsupplied-arg?)
         (prefix-in base: racket/base)
         (except-in racket/list drop)
         (only-in racket/list [drop list-drop])
         (only-in racket/contract/base contract-out)
         polars/private/foreign
         polars/private/expr
         (only-in (submod polars/private/expr internal) lazyframe-collect/who)
         (only-in polars/private/expr-core explain/c lazyframe-explainer)
         polars/private/generic/core
         (only-in polars/private/io-contracts size-max)
         (only-in polars/private/generic/dtype dtype-spec?)
         (only-in polars/private/generic/expr-util col-expr/c))

(provide (except-out (all-defined-out) cast explain head tail slice drop pivot unpivot
                     group-by agg rename with-column)
         (contract-out
          [cast (-> (or/c Expr-ptr? series? string?) cast-target/c (or/c Expr-ptr? series?))]
          [head (-> rows-source/c count/c any/c)]
          [tail (-> rows-source/c count/c any/c)]
          [slice (-> rows-source/c offset/c count/c any/c)]
          [drop (->i ([x (or/c dataframe? list?)]
                      [arg (x) (if (dataframe? x) column-names/c any/c)])
                     [result any/c])]
          [pivot (->* (dataframe? #:on (listof string?) #:index (listof string?)
                                  #:values (listof string?))
                      (#:agg (or/c #f 'none 'first 'sum 'min 'max 'mean 'count))
                      dataframe?)]
          [unpivot (-> dataframe? #:on (listof string?) #:index (listof string?) dataframe?)]
          [with-column (-> dataframe? series? dataframe?)]
          [group-by (-> (or/c dataframe? lazyframe?) col-expr/c col-expr/c ... grouped?)]
          [agg (-> grouped? Expr-ptr? ... (or/c dataframe? lazyframe?))]
          (rename rename rename (->i ([x (or/c series? dataframe?)] [a string?])
                                     ([b string?])
                                     #:pre/desc (x b)
                                     (or (series? x) (not (unsupplied-arg? b))
                                         "renaming a dataframe column needs old and new names")
                                     [result (or/c series? dataframe?)]))
          [explain (explain/c lazyframe?)]))

(define cast-target/c (or/c dtype-spec? 'binary 'duration))

(define rows-source/c (or/c series? dataframe? lazyframe? Expr-ptr?))

(define offset/c (integer-in (- (expt 2 63)) (sub1 (expt 2 63))))

(define count/c (integer-in 0 size-max))

(define lazy-rows-max (sub1 (expt 2 32)))

(define expr-rows-max (sub1 (expt 2 63)))

(define (clamped-window offset length limit)
  (define start (max offset (- limit)))
  (values start (min limit (max 0 (- length (- start offset))))))

(define column-names/c (or/c string? (listof string?)))

(define (column-height-problem d s)
  (define height (dataframe-height d))
  (define n (series-len s))
  (and (not (= n height))
       (format "unable to add a column of length ~a to a DataFrame of height ~a" n height)))

(define (rename-problem d old new)
  (define present (dataframe-column-names d))
  (cond
    [(column-problem present (list old)) => values]
    [(member new present) (format "column '~a' is duplicate" new)]
    [else #f]))

(define (collect-frame who d extend)
  (wrap-dataframe (lazyframe-collect/who who (extend (dataframe-lazy d)))))

(define (filter . args)
  (match args
    [(list (? dataframe? d) (? Expr-ptr? pred))
     (collect-frame 'filter d (lambda (plan) (lazyframe-filter plan pred)))]
    [(list (? dataframe? d) (? series? mask))
     (collect-frame 'filter d (lambda (plan) (lazyframe-filter plan (expr-lit-series mask))))]
    [(list (? lazyframe? lf) (? Expr-ptr? pred))
     (wrap-lazyframe (lazyframe-filter lf pred))]
    [(list (? Expr-ptr? e) (? Expr-ptr? pred))
     (expr-filter e pred)]   ; column-level filter; length-changing, use in select
    [_ (apply base:filter args)]))

(define (head x n)
  (cond [(series? x)    (wrap-series    (series-head x n))]
        [(dataframe? x) (wrap-dataframe (dataframe-head x n))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-head x (min n lazy-rows-max)))]
        [else           (expr-head x #:n (min n expr-rows-max))]))

(define (tail x n)
  (cond [(series? x)    (wrap-series    (series-tail x n))]
        [(dataframe? x) (wrap-dataframe (dataframe-tail x n))]
        [(lazyframe? x) (wrap-lazyframe (lazyframe-tail x (min n lazy-rows-max)))]
        [else           (expr-tail x #:n (min n expr-rows-max))]))

(define (slice x offset length)
  (cond [(series? x)    (wrap-series    (series-slice x offset length))]
        [(dataframe? x) (wrap-dataframe (dataframe-slice x offset length))]
        [(lazyframe? x)
         (define-values (start rows) (clamped-window offset length lazy-rows-max))
         (wrap-lazyframe (lazyframe-slice x start rows))]
        [else
         (define-values (start rows) (clamped-window offset length expr-rows-max))
         (expr-slice x start rows)]))

(define (unique x)
  (cond [(series? x)    (wrap-series    (series-unique x))]
        [(dataframe? x) (wrap-dataframe (dataframe-unique x))]
        [else (error 'unique "expected a series or dataframe, got ~v" x)]))

(define (drop-nulls x)
  (cond [(series? x)    (wrap-series    (series-drop-nulls x))]
        [(dataframe? x) (wrap-dataframe (dataframe-drop-nulls x))]
        [(Expr-ptr? x)  (expr-drop-nulls x)]   ; length-changing; use inside select
        [else (error 'drop-nulls "expected a series, dataframe, or Expr, got ~v" x)]))

(define (reverse x)
  (cond [(series? x)   (wrap-series (series-reverse x))]
        [(Expr-ptr? x) (expr-reverse x)]
        [(list? x)     (base:reverse x)]
        [else (error 'reverse "expected a series, Expr, or list, got ~v" x)]))

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
  (cond
    [(dataframe? d)
     (collect-frame 'select d (lambda (plan) (lazyframe-select plan (specs->exprs 'select d specs))))]
    [(lazyframe? d)
     (wrap-lazyframe (lazyframe-select d (specs->exprs 'select d specs)))]
    [else (error 'select "expected a dataframe or lazyframe, got ~v" d)]))

;; with-columns: add/replace columns in one pass (Polars df.with_columns).
;; Same variadic, expression-aware specs as select, but keeps the existing
;; columns and appends the (typically aliased) derived ones.
(define (with-columns d . specs)
  (cond
    [(dataframe? d)
     (collect-frame 'with-columns d
                    (lambda (plan) (lazyframe-with-columns plan (specs->exprs 'with-columns d specs))))]
    [(lazyframe? d)
     (wrap-lazyframe (lazyframe-with-columns d (specs->exprs 'with-columns d specs)))]
    [else (error 'with-columns "expected a dataframe or lazyframe, got ~v" d)]))

(define (drop x arg)
  (cond
    [(dataframe? x)
     (define names (if (list? arg) arg (list arg)))
     (wrap-dataframe
      (or (dataframe-drop-columns/c x names)
          (refuse 'drop (column-problem (dataframe-column-names x) names)
                  "cannot drop the columns")))]
    [else (list-drop x arg)]))

(define (with-column d s)
  (wrap-dataframe
   (or (dataframe-with-column/raw d s)
       (refuse 'with-column (column-height-problem d s) "cannot add the column"))))

(define (cast x dtype)
  (cond [(Expr-ptr? x) (expr-cast-to 'cast x dtype)]
        [(series? x)   (wrap-series (series-cast-to 'cast x dtype))]
        [else          (expr-cast-to 'cast (col x) dtype)]))

(define (pivot d #:on on #:index index #:values values #:agg [agg 'first])
  (wrap-dataframe (pivot-frame 'pivot d on index values agg)))

(define (unpivot d #:on on #:index index)
  (wrap-dataframe (unpivot-frame 'unpivot d on index)))

;; --- group-by / agg: the deferred, threading-compatible group handle --------
(struct grouped (frame keys) #:reflection-name 'grouped)

(define (group-by frame . keys)
  (grouped frame keys))

(define (agg g . agg-exprs)
  (define frame (grouped-frame g))
  (define keys (grouped-keys g))
  ;; dispatch on whether the grouped frame is eager or lazy
  (if (lazyframe? frame)
      (wrap-lazyframe (lazyframe-group-by-agg frame keys agg-exprs))
      (collect-frame 'agg frame (lambda (plan) (lazyframe-group-by-agg plan keys agg-exprs)))))

;; --- lazy: a DataFrame's deferred query plan, and back ----------------------
(define (lazy d)
  (guard-dataframe 'lazy d)
  (wrap-lazyframe (dataframe-lazy d)))

(define (collect lf)
  (unless (lazyframe? lf)
    (error 'collect "expected a lazyframe, got ~v" lf))
  (wrap-dataframe (lazyframe-collect/who 'collect lf)))

(define explain (lazyframe-explainer 'explain))

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

(define (rename x a [b unset])
  (cond
    [(series? x)
     (define c (series-clone x))
     (series-rename c a)
     c]
    [else
     (wrap-dataframe
      (or (dataframe-rename/raw x a b)
          (refuse 'rename (rename-problem x a b) "cannot rename the column")))]))

(module+ test
  (require rackunit (only-in threading ~>)
           polars/private/generic/core
           polars/private/generic/operators
           (only-in polars/private/foreign dataframe-sort)
           polars/private/generic/reductions
           polars/private/generic/test-fixtures
           (prefix-in contracted: (submod "..")))

  (define (sorted-by d key) (wrap-dataframe (dataframe-sort d (list key))))

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

  ;; the unique / drop-nulls reference entry
  (define ref-dups
    (dataframe (list (series (list 1 1 2 polars-null) #:name "v")
                     (series '("a" "a" "b" "c") #:name "w"))))
  (define ref-unique (sorted-by (unique ref-dups) "v"))
  (check-equal? (column ref-unique "v") (list polars-null 1 2))
  (check-equal? (column ref-unique "w") '("c" "a" "b"))
  (check-equal? (series-cells (drop-nulls (ref ref-dups "v"))) '(1 1 2))
  (check-equal? (column (drop-nulls ref-dups) "v") '(1 1 2))
  (check-equal? (column (drop-nulls ref-dups) "w") '("a" "a" "b"))
  (check-exn #rx"^unique: expected a series or dataframe, got '\\(1 1 2\\)$"
             (lambda () (unique '(1 1 2))))

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
  ;; chained when / then / else-when / otherwise -> bucketed values
  (let ([d (with-columns
            (dataframe (list (series '(-3 0 4 12 7) #:name "x" #:dtype 'i32)))
            (alias (~> (p-when (< (col "x") 0)) (then 0)
                       (else-when (= (col "x") 0)) (then 1)
                       (else-when (< (col "x") 10)) (then 2)
                       (otherwise 3))
                   "bucket"))])
    (check-equal? (for/list ([i (in-range 5)]) (ref (ref d #:columns "bucket") i))
                  '(0 1 2 3 2)))
  ;; cast: eager series, and Expr via with-columns
  (check-equal? (dtype (cast (series '(1 2 3) #:dtype 'i32) 'float64)) 'float64)
  (let ([d (with-columns frame (~> (col "score") (cast 'float64) (alias "scoref")))])
    (check-equal? (dtype (ref d #:columns "scoref")) 'float64))
  (check-equal? (dtype (contracted:cast (series '(1 2 3)) 'f64)) 'float64)
  (check-equal? (series-cells (cast (series '(1 2 3)) 'str)) '("1" "2" "3"))
  (check-equal? (series-cells (p/ (cast (series '(1 2 4)) 'f64))) '(1.0 0.5 0.25))
  (let ([d (with-columns frame (contracted:cast "score" 'f32))])
    (check-equal? (dtype (ref d #:columns "score")) 'float32))
  (check-exn #rx"^cast: contract violation\n  expected: \\(or/c dtype-spec\\? \\(quote binary\\)"
             (lambda () (contracted:cast (series '(1 2 3)) 'f65)))
  (define cast-target? (flat-contract-predicate cast-target/c))
  (for ([target '(f64 float64 i32 str bool binary null duration date time categorical
                  datetime (datetime milliseconds) (datetime microseconds #f)
                  (duration nanoseconds) (enum a b))])
    (check-true (cast-target? target) (format "~v" target)))
  (for ([target '(f65 float decimal (decimal 10 2) (list int32) (enum a a) "f64"
                  (datetime microseconds todo-timezone))])
    (check-false (cast-target? target) (format "~v" target)))
  (check-exn #rx"^cast: contract violation\n  expected: \\(or/c Expr-ptr\\? series\\? string\\?\\)"
             (lambda () (contracted:cast 5 'f64)))
  (check-exn #rx"^cast: 1 of 2 "
             (lambda () (contracted:cast (series '("UA" "B6")) '(enum UA AA))))
  (check-exn #rx"^cast: 3 of 4 "
             (lambda () (cast (series (list 'TEB polars-null 'XYZ 'TEB 'EWR)) '(enum EWR JFK LGA))))
  (check-equal? (series-cells (cast (series (list 'EWR polars-null 'LGA)) '(enum EWR JFK LGA)))
                (list 'EWR polars-null 'LGA))
  (check-exn #rx"^cast: 2 of 2 "
             (lambda () (cast (series '(high high) #:dtype '(enum high)) '(enum low))))

  ;; categorical / enum casts: symbols out, lexical vs declared order, strict enum
  (define flights
    (dataframe (list (series '("UA" "AA" "UA" "B6") #:name "carrier")
                     (series '("IAH" "MIA" "IAH" "JFK") #:name "dest")
                     (series '(10 20 30 40) #:name "n"))))
  (define coded (with-columns flights (cast "carrier" 'categorical)
                  (cast "dest" '(enum JFK MIA IAH))))
  (check-equal? (dtype (ref coded "carrier")) 'categorical)
  (check-equal? (dtype (ref coded "dest")) '(enum JFK MIA IAH))
  (check-equal? (series-cells (ref coded "carrier")) '(UA AA UA B6))
  (check-equal? (column (sorted-by coded "carrier") "carrier") '(AA B6 UA UA))
  (check-equal? (column (sorted-by coded "dest") "dest") '(JFK MIA IAH IAH))
  (check-equal? (column (filter coded (= (col "carrier") 'UA)) "n") '(10 30))
  (check-equal? (column (filter coded (> (col "dest") "MIA")) "n") '(10 30))
  (check-equal? (~> coded (group-by "carrier") (agg (alias (sum "n") "n"))
                    (sorted-by "carrier") (column "n"))
                '(20 40 40))
  (check-equal? (column-names (select coded (col 'categorical))) '("carrier"))
  (check-equal? (column-names (select coded (col '(enum JFK MIA IAH)))) '("dest"))
  (check-equal? (column-names (select coded (col '(enum JFK MIA)))) '())
  (check-equal? (series-cells (= (ref coded "carrier") 'UA)) '(#t #f #t #f))
  (check-equal? (series-cells (cast (ref coded "dest") 'string)) '("IAH" "MIA" "IAH" "JFK"))
  (check-exn #rx"^cast: 3 of 4 "
             (lambda () (cast (ref flights "dest") '(enum JFK))))
  (check-exn #rx"^with-columns: [^\n]*\"IAH\""
             (lambda () (with-columns flights (cast "dest" '(enum JFK MIA)))))
  (define nul-dests (list 'enum 'JFK (string->symbol "MI\u0000A") 'IAH))
  (for ([target (list (ref flights "dest") "dest")])
    (check-exn #rx"^cast: contract violation\n  expected: an enum category without a NUL"
               (lambda () (cast target nul-dests))))

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

  (let* ([sales (dataframe (list (series '("a" "a" "b" "b")     #:name "store")
                                 (series '("q1" "q2" "q1" "q2") #:name "quarter")
                                 (series '(10 20 30 40)         #:name "sales" #:dtype 'i32)))]
         [pv (pivot sales #:on '("quarter") #:index '("store") #:values '("sales") #:agg 'sum)])
    (check-equal? (sort (column-names pv) string<?) '("q1" "q2" "store"))
    (check-equal? (height pv) 2)
    (check-equal? (height (unpivot pv #:on '("q1" "q2") #:index '("store"))) 4))
  (let* ([cells (dataframe (list (series '(1 1 2 2 2) #:name "id")
                                 (series '("x" "y" "x" "y" "y") #:name "k")
                                 (series '(10 11 20 21 22) #:name "v")))]
         [pv (sorted-by (pivot cells #:on '("k") #:index '("id") #:values '("v")) "id")])
    (check-equal? (column-names pv) '("id" "x" "y"))
    (check-equal? (dtype (ref pv "y")) 'int64)
    (check-equal? (column pv "y") '(11 21))
    (check-exn #rx"^pivot: cannot pivot the dataframe: "
               (lambda () (pivot cells #:on '("k") #:index '("id") #:values '("v") #:agg #f))))
  (let* ([gaps (dataframe (list (series '(1 2 2) #:name "id")
                                (series '("y" "x" "y") #:name "k")
                                (series (list 10 polars-null 21) #:name "v")))]
         [sums (sorted-by (pivot gaps #:on '("k") #:index '("id") #:values '("v") #:agg 'sum) "id")]
         [counts (sorted-by (pivot gaps #:on '("k") #:index '("id") #:values '("v") #:agg 'count) "id")]
         [inferred (sorted-by (pivot gaps #:on '("k") #:index '() #:values '("v") #:agg 'sum) "id")])
    (check-equal? (column-names sums) '("id" "x" "y"))
    (check-equal? (column sums "x") '(0 0))
    (check-equal? (column counts "x") '(0 1))
    (check-equal? (dtype (ref counts "x")) 'uint32)
    (check-equal? (column-names inferred) '("id" "x" "y")))
  (let ([numeric (dataframe (list (series '(1 1) #:name "id")
                                  (series '(10 2) #:name "k")
                                  (series '(5 6) #:name "v")))])
    (check-equal? (column-names (pivot numeric #:on '("k") #:index '("id") #:values '("v")))
                  '("id" "2" "10")))
  (let* ([wide (dataframe (list (series '(1 2) #:name "id")
                                (series '(10 20) #:name "a")
                                (series '(30 40) #:name "b")))]
         [long (unpivot wide #:on '() #:index '("id"))])
    (check-equal? (column-names long) '("id" "variable" "value"))
    (check-equal? (column long "variable") '("a" "a" "b" "b")))

  (for ([refusal
         (list (list 'select (lambda () (select ops-df (col "nope"))))
               (list 'with-columns (lambda () (with-columns ops-df (p+ (col "nope") 1))))
               (list 'filter (lambda () (filter ops-df (> (col "nope") 1))))
               (list 'agg (lambda () (~> ops-df (group-by "group") (agg (sum "nope")))))
               (list 'agg (lambda () (~> ops-df (group-by "nope") (agg (sum "value")))))
               (list 'collect (lambda () (~> ops-df lazy (select "nope") collect)))
               (list 'collect (lambda () (~> ops-df lazy (filter (> (col "nope") 2)) collect))))])
    (match-define (list who thunk) refusal)
    (define message
      (pregexp (format "^~a: not found: unable to find column \"nope\"; valid columns: \\[[^\n]*\\]$" who)))
    (check-exn (lambda (e) (and (not (exn:fail:contract? e)) (regexp-match? message (exn-message e))))
               thunk
               (object-name message)))
  (check-pred lazyframe? (lazy ops-df))
  ;; lazy head / tail / slice (build the plan, then collect)
  (check-equal? (height (~> ops-df lazy (head 2) collect)) 2)
  (check-equal? (height (~> ops-df lazy (tail 2) collect)) 2)
  (check-equal? (height (~> ops-df lazy (slice 1 3) collect)) 3))

(module+ test
  (require racket/runtime-path
           (only-in racket/contract exn:fail:contract:blame?)
           (only-in racket/string string-contains?)
           (only-in polars/private/csv lazyframe-scan-csv)
           (prefix-in contracted: (submod "..")))
  (define-runtime-path iris-csv "../../scribblings/guide/iris.csv")
  (define iris-plan
    (~> (wrap-lazyframe (lazyframe-scan-csv iris-csv))
        (filter (> (col "sepal_length") 5))
        (group-by "species")
        (agg (mean "sepal_width"))))
  (define iris-explained (contracted:explain iris-plan))
  (check-true (string-contains? iris-explained "AGGREGATE"))
  (check-true (string-contains? iris-explained "Csv SCAN ["))
  (check-true (string-contains? iris-explained "SELECTION: col(\"sepal_length\") > 5.0"))
  (check-false (string-contains? (contracted:explain iris-plan #:optimized #f) "SELECTION"))
  (check-not-equal? (contracted:explain iris-plan #:format 'tree) iris-explained)
  (check-equal? (object-name contracted:explain) 'explain)
  (check-exn exn:fail:contract:blame? (lambda () (contracted:explain ops-df)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:explain iris-plan #:format 'dot)))
  (check-exn exn:fail:contract:blame? (lambda () (contracted:explain iris-plan #:optimized 1)))
  (check-regexp-match
   #rx"^explain: failed to explain the query: [^\n]*\"nope\""
   (with-handlers ([exn:fail? exn-message])
     (contracted:explain (select (lazy ops-df) "nope")))))
