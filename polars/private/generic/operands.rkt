#lang racket/base

(require (only-in racket/format ~r)
         (only-in racket/list make-list)
         (only-in racket/match match match* match-define)
         (only-in racket/math infinite? nan?)
         (only-in polars/private/foreign
                  call/foreign-error dataframe-column dataframe-drop dataframe-new enum-dtype?
                  polars-null? series-drop series-dtype series-len series-name)
         (only-in polars/private/expr
                  expr-alias expr-all expr-drop lazyframe-collect/raw lazyframe-select lit/who)
         (only-in (submod polars/private/expr internal) call-with-plan)
         (only-in polars/private/generic/core series? wrap-series)
         (only-in polars/private/generic/dtype
                  coerce-elements dtype->constructor numeric-dtype? temporal-dtype?)
         (only-in polars/private/resource with-release)
         (only-in polars/private/series series-repeat-temporal)
         (only-in polars/private/temporal temporal-encoder temporal-value-dtype))

(provide call-with-logical-operand
         call-with-operand-series
         const-series
         expression-form-op
         operand-action
         series-through-expr)

(define (const-series who dt n value #:name [name ""])
  (wrap-series
   (if (temporal-dtype? dt)
       (series-repeat-temporal who name value n dt)
       ((dtype->constructor dt #f) name (coerce-elements dt (make-list n value))))))

(define integer-ranges
  (for*/hasheq ([bits (in-list '(8 16 32 64))]
                [kind (in-list '(int uint))])
    (define limit (expt 2 bits))
    (values (string->symbol (format "~a~a" kind bits))
            (match kind
              ['int (cons (- (quotient limit 2)) (sub1 (quotient limit 2)))]
              ['uint (cons 0 (sub1 limit))]))))

(define (int64-value? v)
  (match-define (cons low high) (hash-ref integer-ranges 'int64))
  (<= low v high))

(define (operator-classes who)
  (match who
    ['+ '(add arithmetic)]
    ['* '(mul arithmetic)]
    ['/ '(div arithmetic)]
    ['mod '(mod arithmetic)]
    ['- '(arithmetic)]
    [(or '= '!= '< '> '<= '>=) '(compare)]))

(define (dtype-classes dt)
  (match dt
    [(or 'int8 'int16 'int32 'int64 'uint8 'uint16 'uint32 'uint64) '(integer numeric)]
    [(or 'float32 'float64) '(float numeric)]
    [(list 'decimal _ _) '(decimal)]
    [(? enum-dtype?) '(enum)]
    [(or 'date 'time) (list dt 'temporal)]
    [(list (and kind (or 'datetime 'duration)) _ ...) (list kind 'temporal)]
    [(or 'string 'categorical 'boolean 'null) (list dt)]
    [_ '(other)]))

(define (operand-class dt v)
  (match v
    [(? series?) 'series]
    [(? polars-null?) 'null]
    [(? boolean?) 'boolean]
    [(? exact-integer?)
     (match (hash-ref integer-ranges dt #f)
       [#f (if (int64-value? v) 'integer 'huge-integer)]
       [(cons low high)
        (cond
          [(<= low v high) 'integer]
          [(and (int64-value? v) (not (and (zero? low) (negative? v)))) 'wide-integer]
          [(int64-value? v) 'negative-integer]
          [else 'other])])]
    [(? real?) 'real]
    [(or (? string?) (? symbol?)) 'text]
    [_ (match (temporal-value-dtype v)
         [(and kind (or 'date 'time)) kind]
         [(list 'datetime _ #f) 'datetime]
         [(list 'datetime _ _) 'moment]
         [(list 'duration _) 'duration]
         [#f 'other])]))

(define operand-rules
  '([mod        temporal              _                                   modulo]
    [_          _                     series                              series]
    [div        null                  null                                same]
    [_          _                     null                                expression]
    [_          null                  (boolean integer real text date time datetime moment duration)
                                      expression]
    [_          enum                  text                                expression]
    [add        _                     text                                (sided expression string)]
    [_          decimal               (integer real)                      expression]
    [compare    decimal               boolean                             integer-expression]
    [div        decimal               boolean                             (sided float64 expression)]
    [arithmetic decimal               boolean                             expression]
    [mul        duration              (integer real)                      expression]
    [div        duration              (integer real)                      (sided refuse float64)]
    [div        float                 (integer real)                      (sided float64 expression)]
    [div        boolean               (integer huge-integer)              (sided refuse float64)]
    [div        integer               real                                (sided float64 expression)]
    [_          integer               wide-integer                        expression]
    [div        integer               negative-integer                    expression]
    [compare    (string categorical)  text                                same]
    [compare    string                (integer huge-integer real boolean) python-str]
    [compare    (string categorical)  (date time)                         own]
    [compare    date                  (date datetime moment)              own]
    [compare    datetime              (datetime moment)                   own]
    [compare    duration              duration                            own]
    [compare    time                  time                                own]
    [mod        float                 date                                refuse]
    [mod        float                 (datetime moment)                   physical]
    [arithmetic _                     time                                refuse]
    [arithmetic _                     (date datetime moment duration)     own]
    [arithmetic float                 text                                refuse]
    [arithmetic _                     text                                string]
    [arithmetic (boolean string)      real                                float64]
    [_          numeric               boolean                             same]
    [_          float                 (integer huge-integer real)         same]
    [_          integer               integer                             same]
    [_          integer               real                                float64]
    [_          boolean               boolean                             same]))

(define (matches? pattern classes)
  (match pattern
    ['_ #t]
    [(? symbol?) (and (memq pattern classes) #t)]
    [(? list?) (ormap (lambda (p) (and (memq p classes) #t)) pattern)]))

(define (operand-action who dt v side)
  (define ops (operator-classes who))
  (define dts (dtype-classes dt))
  (define value (list (operand-class dt v)))
  (define rule
    (for/or ([r (in-list operand-rules)])
      (match r
        [(list op-pattern dt-pattern value-pattern action)
         #:when (and (matches? op-pattern ops) (matches? dt-pattern dts)
                     (matches? value-pattern value))
         action]
        [_ #f])))
  (match* (rule side)
    [((list 'sided left _) 'left) left]
    [((list 'sided _ right) 'right) right]
    [(#f _) 'refuse]
    [(action _) action]))

(define (same-value dt v)
  (match v
    [(? boolean?) #:when (numeric-dtype? dt) (same-value dt (if v 1 0))]
    [(? real?) #:when (memq dt '(float32 float64)) (exact->inexact v)]
    [(? symbol?) (symbol->string v)]
    [_ v]))

(define (python-str v)
  (match v
    [#t "True"]
    [#f "False"]
    [(? exact-integer?) (number->string v)]
    [_ (python-float-text (exact->inexact v))]))

(define (python-float-text x)
  (cond
    [(nan? x) "nan"]
    [(infinite? x) (if (positive? x) "inf" "-inf")]
    [else
     (match-define (list _ sign whole fraction exponent)
       (regexp-match #rx"^(-?)([0-9]+)(?:[.]([0-9]+))?(?:e([-+]?[0-9]+))?$" (number->string x)))
     (define all-digits (string-append whole (or fraction "")))
     (define leading (string-length (car (regexp-match #rx"^0*" all-digits))))
     (define digits (regexp-replace #rx"0*$" (substring all-digits leading) ""))
     (define point (- (+ (string-length whole) (if exponent (string->number exponent) 0)) leading))
     (string-append sign (python-digits (nearest-digits (abs x) digits point) point))]))

(define (nearest-digits x digits point)
  (define n (string-length digits))
  (define shortest (string->number digits))
  (define exact (inexact->exact x))
  (define (value c) (* c (expt 10 (- point n))))
  (define (rank c) (list (abs (- (value c) exact)) (if (even? c) 0 1)))
  (define (before? a b)
    (match* ((rank a) (rank b))
      [((list da pa) (list db pb)) (or (< da db) (and (= da db) (< pa pb)))]))
  (match shortest
    [#f digits]
    [_
     (define candidates
       (for/list ([c (in-list (list shortest (sub1 shortest) (add1 shortest)))]
                  #:when (and (= (string-length (number->string c)) n)
                              (= (exact->inexact (value c)) x)))
         c))
     (regexp-replace #rx"0*$" (number->string (car (sort candidates before?))) "")]))

(define (python-digits digits point)
  (define n (string-length digits))
  (define scientific (sub1 point))
  (cond
    [(zero? n) "0.0"]
    [(or (< scientific -4) (>= scientific 16))
     (string-append (substring digits 0 1) (if (> n 1) (string-append "." (substring digits 1)) "")
                    (if (negative? scientific) "e-" "e+")
                    (~r (abs scientific) #:min-width 2 #:pad-string "0"))]
    [(<= point 0) (string-append "0." (make-string (- point) #\0) digits)]
    [(>= point n) (string-append digits (make-string (- point n) #\0) ".0")]
    [else (string-append (substring digits 0 point) "." (substring digits point))]))

(define (operand-series who s other side)
  (define dt (series-dtype s))
  (define n (series-len s))
  (define (lifted dtype value) (const-series who dtype n value #:name (series-name s)))
  (define o
    (match (operand-action who dt other side)
      ['series other]
      ['same (lifted dt (same-value dt other))]
      ['own (lifted (temporal-value-dtype other) other)]
      ['float64 (lifted 'float64 (same-value 'float64 other))]
      ['physical
       (match-define (list 'datetime _ zone) (temporal-value-dtype other))
       (define encode (temporal-encoder who (list 'datetime 'microseconds zone)))
       (lifted dt (same-value dt (encode other)))]
      ['string (lifted 'string (same-value 'string other))]
      ['python-str (lifted 'string (python-str other))]
      ['modulo (raise-arguments-error who "cannot take the modulo of a temporal dtype"
                                      "series dtype" dt)]
      [_ (raise-arguments-error who "the value cannot be an element of a series of this dtype"
                                "value" other "series dtype" dt)]))
  (match* (dt (series-dtype o))
    [((list 'datetime _ zone) (list 'datetime _ other-zone))
     #:when (not (equal? zone other-zone))
     (raise-arguments-error who "datetimes in different time zones"
                            "series dtype" dt "other dtype" (series-dtype o))]
    [(_ _) o]))

(define (logical-operand who s other)
  (cond
    [(series? other) other]
    [(or (boolean? other) (polars-null? other))
     (const-series who 'boolean (series-len s) other #:name (series-name s))]
    [else (raise-argument-error who "(or/c series? boolean? polars-null?)" other)]))

(define (call-with-lifted lifted other proc)
  (define release (if (eq? lifted other) void series-drop))
  (with-release ([operand lifted release])
    (proc operand)))

(define (call-with-operand-series who s other side proc)
  (call-with-lifted (operand-series who s other side) other proc))

(define (call-with-logical-operand who s other proc)
  (call-with-lifted (logical-operand who s other) other proc))

(define (series-through-expr who s build)
  (define name (series-name s))
  (define (collect plan)
    (call/foreign-error who (lambda () (lazyframe-collect/raw plan))))
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [all (expr-all) expr-drop]
                 [built (build all) expr-drop]
                 [named (expr-alias built name) expr-drop]
                 [out (call-with-plan frame
                                      (lambda (source) (lazyframe-select source (list named)))
                                      collect)
                      dataframe-drop])
    (wrap-series (dataframe-column out name))))

(define (expression-form-op who expr-op a b)
  (define (literal s v side)
    (match (and (series? s) (not (series? v)) (operand-action who (series-dtype s) v side))
      ['expression (list v)]
      ['integer-expression (list (if v 1 0))]
      [_ #f]))
  (match* ((literal a b 'right) (literal b a 'left))
    [((list value) _)
     (with-release ([v (lit/who who value) expr-drop])
       (series-through-expr who a (lambda (e) (expr-op e v))))]
    [(_ (list value))
     (with-release ([v (lit/who who value) expr-drop])
       (series-through-expr who b (lambda (e) (expr-op v e))))]
    [(_ _) #f]))

(module+ test
  (require rackunit
           (only-in polars/private/expr expr-add expr-neg)
           (only-in polars/private/expr-core col expr-drop-count lazyframe-drop-count)
           (only-in polars/private/foreign polars-null series-new-i64 series-ref)
           (only-in polars/private/test-helpers settle!)
           (only-in gregor date))
  (define (noting build)
    (define given (box '()))
    (values given
            (lambda operands
              (define built (apply build operands))
              (set-box! given (cons built operands))
              built)))
  (define (check-all-dropped exprs)
    (for ([e (in-list exprs)])
      (check-exn #rx"^expr-drop: expression has been dropped" (lambda () (expr-drop e)))))
  (define ints (wrap-series (series-new-i64 "x" '(1 2))))

  (for ([v (list 1 -7 (expt 2 63) 1/3 2.5 1.0 -0.0 0.0 1e-5 0.0001 1e16 1e22 123456789.0 5e-324
                 0.30000000000000004 12345678901234567890.0 +inf.0 -inf.0 +nan.0 -2.5e-10
                 651483685541104.2 -651483685541104.2 #t #f)]
        [text (list "1" "-7" "9223372036854775808" "0.3333333333333333" "2.5" "1.0" "-0.0" "0.0"
                    "1e-05" "0.0001" "1e+16" "1e+22" "123456789.0" "5e-324" "0.30000000000000004"
                    "1.2345678901234567e+19" "inf" "-inf" "nan" "-2.5e-10"
                    "651483685541104.2" "-651483685541104.2" "True" "False")])
    (check-equal? (python-str v) text))
  (check-equal? (operand-action '+ 'int64 "x" 'left) 'expression)
  (check-equal? (operand-action '+ 'int64 "x" 'right) 'string)
  (check-equal? (operand-action 'mod 'date 2 'right) 'modulo)
  (check-equal? (operand-action 'mod 'int64 (date 2024 1 1) 'right) 'own)

  (let-values ([(given negate) (noting expr-neg)])
    (check-equal? (series-ref (series-through-expr '- ints negate) 1) -2)
    (check-equal? (length (unbox given)) 2)
    (check-all-dropped (unbox given)))

  (let-values ([(given add) (noting expr-add)])
    (check-pred polars-null? (series-ref (expression-form-op '+ add ints polars-null) 0))
    (check-equal? (length (unbox given)) 3)
    (check-all-dropped (unbox given)))

  (settle!)
  (let ([before (expr-drop-count)]
        [plans-before (lazyframe-drop-count)])
    (expression-form-op '+ expr-add ints polars-null)
    (check >= (- (expr-drop-count) before) 4)
    (check-equal? (- (lazyframe-drop-count) plans-before) 2))
  (settle!)
  (let ([plans-before (lazyframe-drop-count)])
    (check-exn exn:fail? (lambda () (series-through-expr '- ints (lambda (e) (col "absent")))))
    (check-equal? (- (lazyframe-drop-count) plans-before) 2)))
