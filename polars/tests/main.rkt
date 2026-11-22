#lang racket/base

(module+ test
  (require rackunit
           (only-in racket/list append-map check-duplicates remove-duplicates)
           racket/match
           racket/runtime-path
           (only-in racket/set list->seteq set-subtract set->list subset?)
           (only-in racket/string string-prefix?)
           (only-in scribble/reader read-inside)
           (only-in setup/getinfo get-info/full)
           (only-in version/utils valid-version?))

  (define-runtime-path collection-dir "..")
  (define-runtime-path package-dir "../..")
  (define-runtime-path manual-path "../scribblings/polars.scrbl")
  (define-runtime-path reference-path "../scribblings/reference.scrbl")

  (test-case "the collection's version is valid and the repository root's matches it"
    (define polars-version ((get-info/full collection-dir) 'version))
    (check-pred valid-version? polars-version)
    (match (get-info/full package-dir)
      [#f (void)]
      [root-info (check-equal? (root-info 'version) polars-version)]))

  (define polars-namespace
    (parameterize ([current-namespace (make-base-empty-namespace)])
      (namespace-require 'polars)
      (current-namespace)))

  (define (phase-0-exports mod)
    (parameterize ([current-namespace polars-namespace])
      (dynamic-require mod (void))
      (define-values (variables syntaxes) (module->exports mod))
      (for*/list ([phase+names (in-list (append variables syntaxes))]
                  #:when (eqv? (car phase+names) 0)
                  [name (in-list (cdr phase+names))])
        (car name))))

  (define (binding-source name)
    (parameterize ([current-namespace polars-namespace])
      (match-define (list source _ ...) (identifier-binding (namespace-symbol->identifier name)))
      (resolved-module-path-name (module-path-index-resolve source))))

  (define (in-collection? source)
    (and (path? source)
         (string-prefix? (path->string (simplify-path source))
                         (path->string (path->directory-path
                                        (simplify-path (path->complete-path collection-dir)))))))

  (define (read-manual path)
    (call-with-input-file path
      (lambda (in)
        (read-line in 'any)
        (read-inside in))))

  (define section-levels '((section . 1) (subsection . 2) (subsubsection . 3)))
  (define def-heads '(defproc defproc* defproc/arguments defform defform* defidform defthing))

  (define (drop-options args)
    (match args
      [(list* (? keyword?) _ rest) (drop-options rest)]
      [_ args]))

  (define (link-target? args)
    (match args
      [(list* '#:link-target? #f _) #f]
      [(list* (? keyword?) _ rest) (link-target? rest)]
      [_ #t]))

  (define (form-names head args)
    (match* (head (if (link-target? args) (drop-options args) '()))
      [(_ '()) '()]
      [((or 'defproc 'defform) (list (cons (? symbol? name) _) _ ...)) (list name)]
      [('defform (list (? symbol? name) _ ...)) (list name)]
      [('defproc* (list (list (list (cons (? symbol? names) _) _ ...) ...) _ ...))
       (remove-duplicates names)]
      [('defform* (list (list (cons (? symbol? names) _) ...) _ ...)) (remove-duplicates names)]
      [('defproc/arguments (list _ (cons (? symbol? name) _) _ ...)) (list name)]
      [((or 'defidform 'defthing) (list (? symbol? name) _ ...)) (list name)]))

  (define (documented-entries forms include [parent (list #f)])
    (define base (add1 (length parent)))
    (define (enter stack level)
      (define enclosing (list-tail stack (max 0 (- (length stack) (+ base level -1)))))
      (cons (car enclosing) enclosing))
    (define (walk form stack)
      (match form
        [(list (? symbol? head) _ ...)
         #:when (regexp-match? #rx"^(define|require)" (symbol->string head))
         (values '() stack)]
        [(list head _ ...)
         #:when (assq head section-levels)
         (values '() (enter stack (cdr (assq head section-levels))))]
        [(list 'defmodule args ...)
         #:when (memq '#:no-declare args)
         (values '() stack)]
        [(list (or 'defmodule 'declare-exporting) args ...)
         (match-define (list mod _ ...) (drop-options args))
         (values '() (cons mod (cdr stack)))]
        [(list 'include-section (? string? included))
         (define document-level (list-tail stack (- (length stack) base)))
         (values (include included document-level) document-level)]
        [(list head args ...)
         #:when (memq head def-heads)
         (values (for/list ([name (in-list (form-names head args))])
                   (cons (car stack) name))
                 stack)]
        [(cons first rest)
         (define-values (first-entries after-first) (walk first stack))
         (define-values (rest-entries after-rest) (walk rest after-first))
         (values (append first-entries rest-entries) after-rest)]
        [_ (values '() stack)]))
    (for/fold ([entries '()]
               [stack (cons (car parent) parent)]
               #:result entries)
              ([form (in-list forms)])
      (define-values (found next) (walk form stack))
      (values (append entries found) next)))

  (define (manual-entries path [parent (list #f)])
    (define-values (dir _name _dir?) (split-path path))
    (documented-entries (read-manual path)
                        (lambda (included parent) (manual-entries (build-path dir included) parent))
                        parent))

  (define (names-of entries mod)
    (for/list ([entry (in-list entries)] #:when (equal? (car entry) mod))
      (cdr entry)))

  (define (sorted-difference a b)
    (sort (set->list (set-subtract (list->seteq a) (list->seteq b))) symbol<?))

  (define (check-same-names what documented exported)
    (with-check-info (['module what])
      (check-equal? (sorted-difference exported documented) '() "exported without an entry")
      (check-equal? (sorted-difference documented exported) '() "documented but not exported")))

  (test-case "an entry belongs to the module of its innermost declaring part"
    (define chapter
      '((title "Chapter")
        (defproc (in-chapter) any/c)
        (section "Low")
        (declare-exporting low)
        (defproc (in-low) any/c)
        (section "Back")
        (defproc (back) any/c)))
    (define document
      '((define-syntax-parser m [(_ (name x)) (syntax (defproc (name) x))])
        (defmodule top)
        (section "A")
        (defproc (a) any/c)
        (deftogether ((defproc #:kind "k" (b (x any/c)) any/c) (defthing c any/c)
                      (defproc #:link-target? #f (b) any/c)))
        (subsection "B")
        (defmodule low #:no-declare)
        (defidform d)
        (defproc* (((e) any/c) ((e (x any/c)) any/c)))
        (subsubsection "C")
        (defmodule low)
        (defform (f x))
        (defform* ((j) (j x)))
        (defform #:id g g)
        (subsection "D")
        (defproc/arguments args (h (p any/c) any/c))
        (section "E")
        (defform #:literals (q) (i q))
        (subsection "F")
        (defmodule low)
        (include-section "chapter.scrbl")
        (defproc (after) any/c)))
    (define (include file parent)
      (check-equal? file "chapter.scrbl")
      (documented-entries chapter include parent))
    (check-equal? (documented-entries document include)
                  '((top . a) (top . b) (top . c) (top . d) (top . e) (low . f) (low . j)
                    (low . g) (top . h) (top . i) (top . in-chapter) (low . in-low) (top . back)
                    (top . after))))

  (define entries (manual-entries manual-path))

  (test-case "the manual documents polars and polars/ffi, each name once"
    (check-equal? (remove-duplicates (map car entries)) '(polars polars/ffi))
    (check-false (check-duplicates (map cdr entries)) "a name with two entries"))

  (define polars-exports (phase-0-exports 'polars))
  (define ffi-exports (phase-0-exports 'polars/ffi))
  (define foreign-re-exports
    (for/list ([name (in-list polars-exports)]
               #:unless (in-collection? (binding-source name)))
      name))

  (test-case "polars re-exports only threading's forms, which threading documents"
    (check-equal? (sort foreign-re-exports symbol<?) '(lambda~> lambda~>> ~> ~>>))
    (check-true (subset? (list->seteq foreign-re-exports)
                         (list->seteq (phase-0-exports 'threading)))))

  (test-case "every export of polars has its entry and every entry its export"
    (check-same-names 'polars
                      (names-of entries 'polars)
                      (set->list (set-subtract (list->seteq polars-exports)
                                               (list->seteq foreign-re-exports)))))

  (test-case "every export of polars/ffi has its entry and every entry its export"
    (check-same-names 'polars/ffi (names-of entries 'polars/ffi) ffi-exports))

  (define (documented-contract forms name arg)
    (let find ([form forms])
      (match form
        [(list 'defproc (list (== name) formals ...) _ ...)
         (for/or ([formal (in-list formals)])
           (match formal
             [(list (== arg) contract _ ...) contract]
             [_ #f]))]
        [(cons first rest) (or (find first) (find rest))]
        [_ #f])))

  (define cast-namespace
    (parameterize ([current-namespace (make-base-empty-namespace)])
      (namespace-require '(only racket/base #%app #%datum quote))
      (namespace-require 'racket/contract/base)
      (namespace-require 'polars)
      (namespace-require '(only polars/ffi series-cast series-new-null))
      (current-namespace)))

  (test-case "series-cast's and cast's entries take the dtypes series-cast takes"
    (define reference (read-manual reference-path))
    (define (series-cast-takes? dtype)
      (parameterize ([current-namespace cast-namespace])
        (with-handlers ([exn:fail? (lambda (_) #f)])
          (eval `(series-cast (series-new-null "s" 1) ',dtype))
          #t)))
    (for* ([verb (in-list '(series-cast cast))]
           [dtype (in-list '(binary duration datetime f64 float64 categorical null
                             (datetime milliseconds) (duration nanoseconds)
                             (datetime microseconds "UTC") (enum a b) nope
                             (datetime seconds)))])
      (define documented
        (parameterize ([current-namespace cast-namespace])
          (eval `(flat-contract-predicate ,(documented-contract reference verb 'dtype)))))
      (check-equal? (documented dtype) (series-cast-takes? dtype) (format "~a ~s" verb dtype)))))
