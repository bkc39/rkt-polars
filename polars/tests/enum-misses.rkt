#lang racket/base

(module+ test
  (require rackunit
           (only-in polars/private/enum-misses enum-misses-reason))

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
    (check-false (enum-misses-reason reason) reason)))
