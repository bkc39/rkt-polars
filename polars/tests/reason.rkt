#lang racket/base

(module+ test
  (require rackunit
           (only-in polars/private/reason respell))

  (check-equal? (respell (string-append "is ambiguous. Please use `ambiguous` to tell how it"
                                        " should be localized. You may be able to use"
                                        " `non_existent='null'` to return `null`"))
                (string-append "is ambiguous. Please use #:ambiguous to tell how it should be"
                               " localized. You may be able to use dt-replace-time-zone's"
                               " #:non-existent 'null to return `null`"))
  (check-equal? (respell "try renaming the columns with `.alias(\"new_name\")` to avoid")
                "try renaming the columns with `(alias expr \"new-name\")` to avoid")
  (for ([hint (list (string-append ", hint: specify this field in the schema, or pass"
                                   " cast_options=pl.ScanCastOptions(extra_struct_fields='ignore')")
                    ", hint: pass cast_options=pl.ScanCastOptions(integer_cast='upcast')")])
    (check-equal? (respell (string-append "encountered extra struct field: x" hint))
                  "encountered extra struct field: x"))
  (check-equal? (respell "a `.` and a \\1 and a & survive") "a `.` and a \\1 and a & survive"))
