#lang racket/base

(require ffi/unsafe
         ffi/unsafe/alloc
         ffi/unsafe/atomic
         (only-in racket/contract/base [-> ->/c] contract-out)
         syntax/parse/define
         (only-in polars/private/c-integer int64/c size/c)
         (only-in polars/private/compat-ffi define-compat)
         (for-syntax racket/base racket/syntax syntax/parse))

(provide (except-out (all-defined-out) dataframe-drop series-drop)
         (contract-out
          [dataframe-drop (->/c DataFrame-ptr? void?)]
          [series-drop (->/c Series-ptr? void?)]))

(define-syntax-parse-rule (provide-row-windows frame?:id head:id tail:id slice:id)
  (provide (contract-out [head (->/c frame? size/c frame?)]
                         [tail (->/c frame? size/c frame?)]
                         [slice (->/c frame? int64/c size/c frame?)])))

;; allocator registers the release on the pointer a wrapper holds, not on the wrapper
(define-values (prop:owned-pointer owned-pointer? owned-pointer-accessor)
  (make-struct-type-property
   'owned-pointer
   (lambda (index info)
     (define field-ref (list-ref info 3))
     (lambda (v) (field-ref v index)))))

(define (owned-pointer-arg args)
  (let unwrap ([v (car args)])
    (if (owned-pointer? v) (unwrap ((owned-pointer-accessor v) v)) v)))

(define (raise-dropped who noun)
  (raise-arguments-error who (format "~a has been dropped" noun)))

(define (dropped? v dropped)
  (and (cpointer? v) (cpointer-has-tag? v dropped)))

(define ((write-owned kind dropped show) v port mode)
  (write-string (if (dropped? v dropped) (format "#<~a: dropped>" kind) (show v)) port))

(define (owned-cpointer-types tag kind noun dropped wrap)
  (define (refuse p)
    (cond
      [(dropped? p dropped) (raise-dropped kind noun)]
      [else (raise-arguments-error (string->symbol (format "~a->C" tag))
                                   (format "argument is not non-null `~a' pointer" tag)
                                   "argument" p)]))
  (define (->c p)
    (cond
      [(and (cpointer? p) (cpointer-has-tag? p tag)) p]
      [else (refuse p)]))
  (define (->racket p)
    (cond
      [p (cpointer-push-tag! p tag)
         (wrap p)]
      [else (refuse p)]))
  (define ((or-null convert) p)
    (and p (convert p)))
  (values (make-ctype _pointer ->c ->racket)
          (make-ctype _pointer (or-null ->c) (or-null ->racket))))

(define (release-owned who noun dropped drop/raw v)
  (call-as-atomic
   (lambda ()
     (define p (owned-pointer-arg (list v)))
     (cond
       [(dropped? p dropped) (raise-dropped who noun)]
       [else (drop/raw p)
             (set-cpointer-tag! p dropped)]))))

(define-syntax-parse-rule (define-owned-cpointer-type
                           type:id
                           kind:id
                           (~alt (~optional
                                  (~seq #:noun noun:str)
                                  #:defaults
                                  ([noun (datum->syntax #'kind (symbol->string (syntax-e #'kind)))]))
                                 (~optional (~seq #:wrap wrap:expr) #:defaults ([wrap #'values]))) ...
                           (~and release ((~datum define-compat) drop/raw:id _ ...)))
  #:do [(define tag (substring (symbol->string (syntax-e #'type)) 1))]
  #:with type/null (format-id #'type "~a/null" #'type)
  #:with type? (format-id #'type "~a?" tag)
  #:with type-tag (format-id #'type "~a-tag" tag)
  #:with tag-name (datum->syntax #'type (string->symbol tag))
  #:with dropped (format-id #'kind "~a-dropped" #'kind)
  #:with drop (format-id #'kind "~a-drop" #'kind)
  (begin
    (define type-tag 'tag-name)
    (define dropped (gensym 'dropped))
    (define (type? v)
      (and (cpointer? v) (or (cpointer-has-tag? v type-tag) (cpointer-has-tag? v dropped))))
    (define-values (type type/null) (owned-cpointer-types type-tag 'kind noun dropped wrap))
    release
    (define (drop v)
      (release-owned 'drop noun dropped drop/raw v))))

(define-owned-cpointer-type _Series-ptr series
  (define-compat series-drop/raw
    (_fun _Series-ptr -> _void)
    #:c-id series_drop
    #:wrap (deallocator)))

(define-compat series-drop-count
  (_fun -> _size))

(define-owned-cpointer-type _DataFrame-ptr dataframe
  (define-compat dataframe-drop/raw
    (_fun _DataFrame-ptr -> _void)
    #:c-id dataframe_drop
    #:wrap (deallocator)))

(define-compat dataframe-drop-count
  (_fun -> _size))

(module+ internal
  (provide dataframe-drop series-drop))
