#lang racket/base

(require (only-in racket/format ~r)
         (only-in racket/list make-list)
         (only-in racket/match match match* match-define)
         (only-in racket/math infinite? nan?)
         (only-in polars/private/foreign
                  call/foreign-error dataframe-column dataframe-drop dataframe-new enum-dtype?
                  polars-null? series-drop series-dtype series-len series-name series-value)
         (only-in polars/private/expr
                  expr-alias expr-all expr-drop expr-eq expr-max expr-min lazyframe-collect/raw
                  lazyframe-select lit/who)
         (only-in (submod polars/private/expr internal) call-with-plan)
         (only-in polars/private/c-integer int64/c)
         (only-in polars/private/expr-core lit-integer/c)
         (only-in polars/private/generic/core series? wrap-series)
         (only-in polars/private/generic/dtype
                  coerce-elements dtype->constructor numeric-dtype? temporal-dtype?)
         (only-in polars/private/resource with-release with-release-pool)
         (only-in polars/private/series series-repeat-temporal)
         (only-in polars/private/temporal temporal-encoder temporal-value-dtype))

(provide call-with-logical-operand
         call-with-operand-series
         const-series
         expression-form-op
         operand-action
         series-through-expr
         series-through-expr/raw)

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

(define operators
  (hasheq '+ (list '(add arithmetic) +)
          '- (list '(sub arithmetic) -)
          '* (list '(mul arithmetic) *)
          '/ '((div arithmetic) #f)
          'mod '((mod arithmetic) #f)
          '= '((compare) #f)
          '!= '((compare) #f)
          '< '((compare) #f)
          '> '((compare) #f)
          '<= '((compare) #f)
          '>= '((compare) #f)))

(define (dtype-classes dt)
  (match dt
    [(or 'int8 'int16 'int32 'int64) '(integer numeric)]
    [(or 'uint8 'uint16 'uint32 'uint64) '(integer numeric)]
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
       [#f (cond
             [(int64/c v) 'integer]
             [(lit-integer/c v) 'past-int64]
             [else 'huge-integer])]
       [(cons low high)
        (cond
          [(<= low v high) 'integer]
          [(and (int64/c v) (not (and (zero? low) (negative? v)))) 'wide-integer]
          [(int64/c v) 'negative-integer]
          [(lit-integer/c v) 'past-int64]
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
    [_          decimal               (integer past-int64 real)           expression]
    [compare    decimal               boolean                             integer-expression]
    [div        decimal               boolean                             (sided float64 expression)]
    [arithmetic decimal               boolean                             expression]
    [mul        duration              (integer real)                      expression]
    [div        duration              (integer real)                      (sided refuse float64)]
    [div        float                 (integer real)                      (sided float64 expression)]
    [div        boolean               integer                             expression]
    [div        integer               real                                (sided float64 expression)]
    [(add sub mul) integer            wide-integer                        checked-expression]
    [div        integer               wide-integer
                                      (sided checked-quotient expression)]
    [_          integer               wide-integer                        expression]
    [div        integer               negative-integer                    expression]
    [compare    (string categorical)  text                                same]
    [compare    string                (integer past-int64 huge-integer real boolean)
                                      python-str]
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
    [_          float                 (integer past-int64 huge-integer real)
                                      same]
    [_          integer               integer                             same]
    [_          integer               real                                float64]
    [_          boolean               boolean                             same]))

(define (matches? pattern classes)
  (match pattern
    ['_ #t]
    [(? symbol?) (and (memq pattern classes) #t)]
    [(? list?) (ormap (lambda (p) (and (memq p classes) #t)) pattern)]))

(define (operand-action who dt v side)
  (match-define (list ops _) (hash-ref operators who))
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

(define (check-same-zone who s o)
  (match* ((series-dtype s) (series-dtype o))
    [((and dt (list 'datetime _ zone)) (and other-dt (list 'datetime _ other-zone)))
     #:when (not (equal? zone other-zone))
     (raise-arguments-error who "datetimes in different time zones"
                            "series dtype" dt "other dtype" other-dt)]
    [(_ _) (void)]))

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
  (call-with-lifted (operand-series who s other side) other
                    (lambda (operand)
                      (check-same-zone who s operand)
                      (proc operand))))

(define (call-with-logical-operand who s other proc)
  (call-with-lifted (logical-operand who s other) other proc))

(define ((collect-for who) plan)
  (call/foreign-error who (lambda () (lazyframe-collect/raw plan))))

(define (series-through-expr who s build)
  (wrap-series (series-through-expr/raw who s build)))

(define (series-through-expr/raw who s build)
  (define name (series-name s))
  (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                 [all (expr-all) expr-drop]
                 [built (build all) expr-drop]
                 [named (expr-alias built name) expr-drop]
                 [out (call-with-plan frame
                                      (lambda (source) (lazyframe-select source (list named)))
                                      (collect-for who))
                      dataframe-drop])
    (dataframe-column out name)))

(define (series-scalars who s build)
  (with-release-pool ([own expr-drop])
    (define names
      (for/list ([reduced (in-list (build (own (expr-all)) own))] [i (in-naturals)])
        (own (expr-alias reduced (number->string i)))))
    (with-release ([frame (dataframe-new (list s)) dataframe-drop]
                   [out (call-with-plan frame
                                        (lambda (source) (lazyframe-select source names))
                                        (collect-for who))
                        dataframe-drop])
      (for/list ([i (in-range (length names))])
        (with-release ([column (dataframe-column out (number->string i)) series-drop])
          (series-value who column 0))))))

(define (on-side side op x value)
  (match side
    ['right (op x value)]
    ['left (op value x)]))

(define (expression-form-op who expr-op a b)
  (define (literal s v side)
    (match (and (series? s) (not (series? v)) (operand-action who (series-dtype s) v side))
      [(and action (or 'expression 'checked-expression 'checked-quotient)) (list v action)]
      ['integer-expression (list (if v 1 0) 'expression)]
      [_ #f]))
  (define (run s value action side)
    (with-release ([v (lit/who who value) expr-drop])
      (fitting-result who s value action side
                      (series-through-expr who s (lambda (e) (on-side side expr-op e v))))))
  (match* ((literal a b 'right) (literal b a 'left))
    [((list value action) _) (run a value action 'right)]
    [(_ (list value action)) (run b value action 'left)]
    [(_ _) #f]))

(define (series-extremes who s)
  (series-scalars who s (lambda (all own) (list (own (expr-min all)) (own (expr-max all))))))

(define (holds-minus-one? who s)
  (equal? (series-scalars who s (lambda (all own)
                                  (list (own (expr-max (own (expr-eq all (own (lit/who who -1)))))))))
          '(#t)))

(define (fitting-result who s value action side out)
  (define result-dtype (series-dtype out))
  (match-define (list _ exact) (hash-ref operators who))
  (define overflows?
    (match* (action (hash-ref integer-ranges result-dtype #f))
      [('checked-expression (cons low high))
       (for/or ([x (in-list (series-extremes who s))] #:unless (polars-null? x))
         (not (<= low (on-side side exact x value) high)))]
      [('checked-quotient (cons low _)) (and (= value low) (holds-minus-one? who s))]
      [(_ _) #f]))
  (cond
    [overflows?
     (with-release ([refused out series-drop])
       (raise-arguments-error who "the result does not fit its dtype"
                              "value" value "series dtype" (series-dtype s)
                              "result dtype" result-dtype))]
    [else out]))

(module+ internal
  (provide python-str))
