#lang racket/base

(module+ test
  (require rackunit
           racket/match
           (only-in racket/string string-replace)
           (only-in polars/private/enum-misses enum-cast-reason enum-misses-reason))

  (define tag "\u0001enum-misses\u0001")
  (define payload
    "{\"categories\":[\"a\"],\"missing\":1,\"total\":2,\"distinct\":1,\"shown\":[\"b\"]}")
  (check-equal? (enum-misses-reason (string-append tag payload))
                "1 of 2 values is not in '(enum a): b")
  (for ([reason (list (string-append "the name '" tag payload "' is duplicate")
                      (string-append " " tag payload)
                      (string-append tag payload " trailing")
                      (string-append tag payload payload)
                      (string-append tag "{")
                      (string-append tag "not json")
                      tag
                      (string-append tag "[1,2]")
                      (string-append tag "{\"categories\":[1],\"missing\":1,\"total\":2,"
                                     "\"distinct\":1,\"shown\":[\"b\"]}")
                      (string-append tag "{\"categories\":[\"a\"],\"missing\":-1,\"total\":2,"
                                     "\"distinct\":1,\"shown\":[\"b\"]}")
                      (string-append tag "{\"categories\":[\"a\"],\"missing\":1.5,\"total\":2,"
                                     "\"distinct\":1,\"shown\":[\"b\"]}")
                      (string-append tag "{\"categories\":[\"a\"],\"missing\":1,\"total\":2,"
                                     "\"distinct\":1,\"shown\":\"b\"}")
                      (string-append tag "{\"categories\":[\"a\"],\"missing\":1,\"total\":2}"))])
    (check-false (enum-misses-reason reason) reason))

  (define enum-hint
    (string-append "\n\nEnsure that all values in the input column are present in the categories"
                   " of the enum datatype."))
  (define too-many "\n\nDid not show all failed cases as there were too many.")
  (define (strict-failure source counts listing [hint enum-hint] #:column [column "c"])
    (format "conversion from `~a` to `enum` failed in column '~a' for ~a values: [~a]~a"
            source column counts listing hint))
  (for ([row (in-list
              `((,(strict-failure "str" "1 out of 2" "\"XX\"") "1 of 2 values is not in the enum: XX")
                (,(strict-failure "str" "1 out of 1" "\"XX\"" "") "1 of 1 value is not in the enum: XX")
                (,(strict-failure "str" "2 out of 4" "\"XX\", \"XX\"")
                 "2 of 4 values are not in the enum: XX")
                (,(strict-failure "cat" "3 out of 3" "\"B6\", \"XX\", \"B6\"" "")
                 "3 of 3 values are not in the enum: B6 XX")
                (,(strict-failure "cat" "12 out of 13" "\"m0\", \"m1\", … \"m9\"" too-many)
                 "12 of 13 values are not in the enum: m0 m1, and 10 more")
                (,(strict-failure "enum" "4 out of 4" "\"a\", \"a\", ... \"b\"" "")
                 "4 of 4 values are not in the enum: a, and 2 more")
                (,(strict-failure "str" "2 out of 2" "\"c\nd\", \"a]b\"")
                 "2 of 2 values are not in the enum: \"c\\nd\" |a]b|")
                (,(strict-failure "str" "1 out of 2" "\"\"") "1 of 2 values is not in the enum: ||")
                (,(strict-failure "str" "1 out of 2" "\"XX\""
                                  (string-append enum-hint "\n\nThis error occurred in the following"
                                                 " expression:\n\tcol(\"c\").strict_cast(Enum([...]))\n"))
                 "1 of 2 values is not in the enum: XX")
                (,(strict-failure "str" "1 out of 2" "\"XX\"" #:column "a, b")
                 "1 of 2 values is not in the enum: XX")))])
    (match-define (list reason message) row)
    (check-equal? (enum-cast-reason reason) message reason))
  (for ([reason (list (strict-failure "str" "1 out of 2" "\"a\"b\"")
                      (strict-failure "str" "1 out of 2" "\"a\u0000b\"")
                      (strict-failure "str" "1 out of 2" "\"XX\"" #:column "it's")
                      (string-append "the name '" (strict-failure "str" "1 out of 2" "\"XX\"")
                                     "' is duplicate")
                      (string-append " " (strict-failure "str" "1 out of 2" "\"XX\""))
                      (string-append (strict-failure "str" "1 out of 2" "\"XX\"") " trailing")
                      (strict-failure "str" "1 out of 2" "\"XX\"" "\n\nYou might want to try:")
                      (strict-failure "str" "1 out of 2" "\"XX\"" "\n\nThis error occurred in")
                      (strict-failure "str" "0 out of 2" "\"XX\"")
                      (strict-failure "str" "3 out of 2" "\"XX\", \"XX\", \"YY\"")
                      (strict-failure "str" "2 out of 4" "\"XX\"")
                      (strict-failure "str" "1 out of 4" "\"XX\", \"YY\"")
                      (strict-failure "str" "4 out of 4" "\"a\", \"b\", \"c\"")
                      (strict-failure "str" "3 out of 4" "\"a\", \"b\", … \"c\"")
                      (strict-failure "str" "5 out of 9" "\"a\", … \"b\", \"c\"")
                      (strict-failure "str" "5 out of 9" "… \"c\"")
                      (strict-failure "str" "2 out of 2" "\"a\",\"b\"")
                      (strict-failure "str" "2 out of 2" "0, 5")
                      (strict-failure "str" "1 out of 2" "")
                      (string-replace (strict-failure "str" "1 out of 2" "\"XX\"") "`enum`" "`date`")
                      (string-replace (strict-failure "str" "1 out of 2" "\"XX\"") "`str`" "`i64`"))])
    (check-false (enum-cast-reason reason) reason)))

