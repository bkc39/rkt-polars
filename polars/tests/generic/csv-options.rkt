#lang racket/base

(module+ test
  (require rackunit
           racket/file
           racket/runtime-path
           (only-in racket/list last make-list range second)
           (only-in racket/dict in-dict)
           (only-in racket/match match-define)
           (only-in racket/string string-append*)
           (only-in threading ~>)
           (prefix-in contracted: polars/private/generic/csv)
           (only-in polars/private/csv float-precision-max)
           (only-in polars/private/generic/core column-names dtype height ref shape)
           (only-in polars/private/generic/csv read-csv scan-csv write-csv)
           (only-in polars/private/generic/reshape collect rename select [filter frame-filter])
           (only-in polars/private/generic/operators [> gt])
           (only-in polars/private/io-contracts size-max)
           polars/tests/generic/test-fixtures
           (submod polars/tests/generic/test-fixtures test))

  (define-runtime-path data-dir "../../scribblings/data")
  (define eager-and-scan
    (list (cons 'eager (eager-reader read-csv)) (cons 'scan (scan-reader scan-csv collect))))
  (define flights (build-path data-dir "flights.tsv"))
  (define part-1 (build-path data-dir "parts" "part-1.csv"))
  (define csv-dir (make-temporary-directory "rkt-polars-csv-options-~a"))
  (define (rows-of df)
    (for/list ([i (in-range (height df))])
      (for/list ([name (in-list (column-names df))]) (list-ref (column df name) i))))

  (define abc (scratch-file csv-dir "abc.csv" "a,b,c\n1,NA,x\nNA,2,-\n3,4,y\n"))
  (define abc-pattern (build-path csv-dir "[a]bc.csv"))

  (define a-only (read-csv abc #:null-values '(("a" . "NA"))))
  (check-equal? (map second (dtypes-of a-only)) '(int64 string string))
  (check-equal? (rows-of a-only) (list (list 1 "NA" "x") (list polars-null "2" "-")
                                       (list 3 "4" "y")))
  (check-equal? (rows-of (read-csv abc #:null-values '(("a" . "NA") ("c" . "-"))))
                (list (list 1 "NA" "x") (list polars-null "2" polars-null) (list 3 "4" "y")))
  (check-true (frame=? a-only (read-csv abc-pattern #:null-values '(("a" . "NA")))))
  (check-readers-agree eager-and-scan abc '((#:null-values . (("a" . "NA")))))
  (check-true (frame=? (read-csv abc #:null-values '()) (read-csv abc)))
  (check-regexp-match
   #rx"^read-csv: failed to read csv from [^:]*abc.csv: not found: unable to find column \"zzz\"; valid columns: \\[\"a\", \"b\", \"c\"\\]"
   (message-of (lambda () (read-csv abc #:null-values '(("zzz" . "NA"))))))
  (check-regexp-match #rx"unable to find column \"zzz\""
                      (message-of (lambda () (collect (scan-csv abc #:null-values '(("zzz" . "NA")))))))

  (check-equal? (column-names (read-csv abc #:columns '("c" "a"))) '("a" "c"))
  (check-equal? (column-names (read-csv abc #:columns '(2 0))) '("a" "c"))
  (check-true (frame=? (read-csv abc #:columns '("c" "a")) (read-csv abc-pattern #:columns '(2 0))))
  (check-true (frame=? (read-csv abc #:columns '()) (read-csv abc)))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: not found: unable to find column \"zzz\""
                      (message-of (lambda () (read-csv abc #:columns '("zzz")))))
  (for ([path (list abc abc-pattern)])
    (check-regexp-match #rx"projection index: 7 is out of bounds for csv schema with length: 3$"
                        (message-of (lambda () (read-csv path #:columns '(7))))))
  (check-equal? (column-names (read-csv abc #:columns '("b") #:row-index-name "i")) '("i" "b"))
  (check-equal? (column-names (read-csv abc #:columns '(1) #:row-index-name "i")) '("i" "b"))

  (check-equal? (column-names (read-csv abc #:new-columns '("x"))) '("x" "b" "c"))
  (check-readers-agree eager-and-scan abc '((#:new-columns . ("x"))))
  (define na-in-a (read-csv abc #:null-values '(("a" . "NA"))))
  (for ([renamed (list (read-csv abc #:new-columns '("x") #:null-values '(("x" . "NA")))
                       (collect (scan-csv abc #:new-columns '("x")
                                          #:null-values '(("x" . "NA")))))])
    (check-equal? (map second (dtypes-of renamed)) '(int64 string string))
    (check-true (frame=? renamed (rename na-in-a "a" "x"))))
  (define swapped-keywords
    '((#:new-columns . ("c" "x" "a")) (#:null-values . (("c" . "NA")))
      (#:row-index-name . "b")))
  (define swapped (apply-keywords read-csv swapped-keywords abc))
  (check-equal? (column-names swapped) '("b" "c" "x" "a"))
  (check-equal? (map second (dtypes-of swapped)) '(uint32 int64 string string))
  (check-equal? (column swapped "b") '(0 1 2))
  (check-equal? (for/list ([name '("c" "x" "a")]) (column swapped name))
                (for/list ([name '("a" "b" "c")]) (column na-in-a name)))
  (check-true (frame=? swapped (collect (apply-keywords scan-csv swapped-keywords abc))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: 4 new column names for a file of 3 columns$"
                      (message-of (lambda () (read-csv abc #:new-columns '("p" "q" "r" "s")))))
  (check-regexp-match #rx"^scan-csv: failed to scan [^:]*abc.csv: 4 new column names for a file of 3 columns$"
                      (message-of (lambda () (scan-csv abc #:new-columns '("p" "q" "r" "s")))))
  (check-regexp-match #rx"duplicate: column with name 'b' has more than one occurrence$"
                      (message-of (lambda () (read-csv abc #:new-columns '("b")))))
  (define headerless (read-csv abc #:has-header #f #:new-columns '("p" "q" "r")))
  (check-equal? (column-names headerless) '("p" "q" "r"))
  (check-equal? (height headerless) 4)
  (define renamed-typed
    (read-csv abc #:new-columns '("x") #:null-values '(("x" . "NA"))
              #:schema-overrides '(("x" . f64))))
  (check-equal? (map second (dtypes-of renamed-typed)) '(float64 string string))
  (check-equal? (column renamed-typed "x") (list 1.0 polars-null 3.0))
  (check-regexp-match #rx"schema overrides name columns not in the file: \"a\"$"
                      (message-of (lambda () (read-csv abc #:new-columns '("x")
                                                       #:schema-overrides '(("a" . f64))))))
  (check-regexp-match #rx"^scan-csv: failed to scan [^:]*nope.csv: "
                      (message-of (lambda () (scan-csv (build-path csv-dir "nope.csv")
                                                       #:new-columns '("x")))))
  (check-equal? (column-names (read-csv abc #:new-columns '("x") #:columns '("x" "c")))
                '("x" "c"))
  (define no-match (build-path csv-dir "*.none"))
  (check-regexp-match #rx"^scan-csv: failed to scan [^:]*[*][.]none: no files match the pattern$"
                      (message-of (lambda () (scan-csv no-match #:new-columns '("x")))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*[*][.]none: no files match the pattern$"
                      (message-of (lambda () (read-csv no-match #:new-columns '("x")))))

  (define indexed (read-csv abc #:row-index-name "i" #:row-index-offset 10))
  (check-equal? (column-names indexed) '("i" "a" "b" "c"))
  (check-equal? (dtype (ref indexed "i")) 'uint32)
  (check-equal? (column indexed "i") '(10 11 12))
  (check-readers-agree eager-and-scan abc '((#:row-index-name . "i") (#:row-index-offset . 10)))
  (define clash "duplicate: cannot add row_index with name 'a': column already exists in file.")
  (check-equal? (cause-of (message-of (lambda () (read-csv abc #:row-index-name "a")))) clash)
  (check-equal? (cause-of (message-of (lambda () (read-csv abc #:row-index-name "a"
                                                           #:columns '("b")))))
                clash)
  (check-regexp-match (regexp-quote clash)
                      (message-of (lambda () (collect (scan-csv abc #:row-index-name "a")))))
  (check-regexp-match #rx"cannot add row_index with name 'x'"
                      (message-of (lambda () (scan-csv abc #:new-columns '("x")
                                                       #:row-index-name "x"))))
  (define offset-overflow "row index from offset 4294967294 overflows u32")
  (check-equal? (cause-of (message-of (lambda () (read-csv abc #:row-index-name "i"
                                                           #:row-index-offset #xFFFFFFFE))))
                offset-overflow)
  (check-readers-agree eager-and-scan abc '((#:row-index-name . "i")
                                         (#:row-index-offset . #xFFFFFFFE)))
  (check-equal? (column (read-csv abc #:row-index-name "i" #:row-index-offset #xFFFFFFFD) "i")
                '(#xFFFFFFFD #xFFFFFFFE #xFFFFFFFF))
  (define tall (build-path csv-dir "tall.csv"))
  (display-lines-to-file (cons "x" (range 200000)) tall)
  (for ([offset (list (- #xFFFFFFFF 200000) (- #xFFFFFFFF 100000))])
    (define kvs `((#:row-index-name . "i") (#:row-index-offset . ,offset)))
    (check-readers-agree eager-and-scan tall kvs)
    (check-readers-agree eager-and-scan (one-file-pattern tall) kvs))
  (check-equal? (~> (read-csv tall #:row-index-name "i" #:row-index-offset (- #xFFFFFFFF 200000))
                    (column "i")
                    last)
                (sub1 #xFFFFFFFF))
  (check-regexp-match #rx"row index from offset 4294867295 overflows u32$"
                      (message-of (lambda () (read-csv tall #:row-index-name "i"
                                                       #:row-index-offset (- #xFFFFFFFF 100000)))))

  (define eol-fixture (build-path data-dir "eol.csv"))
  (check-equal? (rows-of (read-csv eol-fixture #:eol-char #\;)) '(("UA" 1545) ("AA" 1141)))
  (check-equal? (map second (dtypes-of (read-csv eol-fixture #:eol-char #\;))) '(string int64))
  (check-equal? (rows-of (collect (scan-csv eol-fixture #:eol-char #\; #:row-index-name "row"
                                            #:row-index-offset 1)))
                '((1 "UA" 1545) (2 "AA" 1141)))
  (check-readers-agree eager-and-scan eol-fixture '((#:eol-char . #\;) (#:row-index-name . "row")
                                                 (#:row-index-offset . 1)))
  (define eol (scratch-file csv-dir "eol.csv" "a,b;1,x;2,y;"))
  (check-equal? (rows-of (read-csv eol #:eol-char #\;)) '((1 "x") (2 "y")))
  (check-readers-agree eager-and-scan eol '((#:eol-char . #\;)))
  (define ragged (scratch-file csv-dir "ragged.csv" "a,b\n1,x\n2,y,extra\n3\n"))
  (check-regexp-match #rx"found more fields than defined in 'Schema'\n\nConsider setting #:truncate-ragged-lines #t\\.$"
                      (message-of (lambda () (read-csv ragged))))
  (check-equal? (rows-of (read-csv ragged #:truncate-ragged-lines #t))
                (list '(1 "x") '(2 "y") (list 3 polars-null)))
  (check-readers-agree eager-and-scan ragged '((#:truncate-ragged-lines . #t)))
  (define commas (scratch-file csv-dir "commas.csv" "a;b\n1,5;x\n2,25;y\n"))
  (check-equal? (column (read-csv commas #:separator #\;) "a") '("1,5" "2,25"))
  (check-equal? (column (read-csv commas #:separator #\; #:decimal-comma #t) "a") '(1.5 2.25))
  (define quoted-commas (scratch-file csv-dir "quoted-commas.csv" "a,b\n\"1,5\",x\n\"2,25\",y\n"))
  (check-equal? (column (read-csv quoted-commas #:decimal-comma #t) "a") '(1.5 2.25))
  (define preamble (scratch-file csv-dir "preamble.csv" "junk \"quoted\nstill junk\na,b\n1,x\n2,y\n3,z\n"))
  (check-equal? (rows-of (read-csv preamble #:skip-lines 2)) '((1 "x") (2 "y") (3 "z")))
  (check-regexp-match #rx"empty CSV" (message-of (lambda () (read-csv preamble #:skip-rows 2))))
  (check-equal? (rows-of (read-csv preamble #:skip-lines 2 #:skip-rows-after-header 1))
                '((2 "y") (3 "z")))
  (check-readers-agree eager-and-scan preamble '((#:skip-lines . 2) (#:skip-rows-after-header . 1)))
  (define empty-file (scratch-file csv-dir "empty.csv" ""))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*empty.csv: no data: empty CSV$"
                      (message-of (lambda () (read-csv empty-file))))
  (check-equal? (shape (read-csv empty-file #:raise-if-empty #f)) '(0 0))
  (check-equal? (shape (collect (scan-csv empty-file #:raise-if-empty #f))) '(0 0))
  (define gaps (scratch-file csv-dir "gaps.csv" "a,b\n1,\n,x\n"))
  (check-equal? (column (read-csv gaps) "b") (list polars-null "x"))
  (check-equal? (column (read-csv gaps #:missing-utf8-is-empty-string #t) "b") '("" "x"))
  (check-equal? (column (read-csv gaps #:missing-utf8-is-empty-string #t) "a")
                (list 1 polars-null))
  (check-equal? (map second (dtypes-of (read-csv abc #:infer-schema #f #:null-values "NA")))
                '(string string string))
  (check-true (frame=? (read-csv abc #:infer-schema #f #:infer-schema-length 50)
                       (read-csv abc #:infer-schema-length 0)))

  (define stations (build-path data-dir "stations.csv"))
  (define station-frame
    (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
              #:null-values '(("temp" . "-") ("rain" . "n/a")) #:truncate-ragged-lines #t))
  (check-equal? (map second (dtypes-of station-frame)) '(string string string float64 float64 string))
  (check-equal? (rows-of (select station-frame "station" "temp" "rain" "note"))
                (list (list "Oslo" 12.5 0.0 "-") (list "Bergen" polars-null 3.2 polars-null)
                      (list "Tromso" 4.0 polars-null "cold") (list "Narvik" 3.5 1.0 "windy")))
  (check-equal? (column (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
                                  #:null-values '("-" "n/a") #:truncate-ragged-lines #t)
                        "note")
                (list polars-null polars-null "cold" "windy"))
  (check-equal? (column (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
                                  #:null-values '(("temp" . "-") ("rain" . "n/a"))
                                  #:truncate-ragged-lines #t #:missing-utf8-is-empty-string #t)
                        "note")
                '("-" "" "cold" "windy"))
  (define dated-stations
    (read-csv stations #:skip-lines 1 #:separator #\; #:decimal-comma #t
              #:null-values '(("temp" . "-") ("rain" . "n/a")) #:truncate-ragged-lines #t
              #:try-parse-dates #t))
  (check-equal? (map second (dtypes-of dated-stations)) '(string date time float64 float64 string))
  (define stations-out (build-path csv-dir "stations-out.csv"))
  (define (stations-written frame . kvs)
    (keyword-apply write-csv (map car kvs) (map cdr kvs) (list frame stations-out))
    (file->string stations-out))
  (check-equal? (stations-written dated-stations '(#:date-format . "%d.%m.%Y")
                                  '(#:decimal-comma . #t) '(#:null-value . "-")
                                  '(#:separator . #\;) '(#:time-format . "%H:%M"))
                "station;day;at;temp;rain;note\nOslo;01.05.2024;06:00;12,5;0,0;-\nBergen;01.05.2024;06:30;-;3,2;-\nTromso;02.05.2024;07:15;4,0;-;cold\nNarvik;02.05.2024;08:00;3,5;1,0;windy\n")
  (check-equal? (stations-written (select dated-stations "station" "temp")
                                  '(#:float-precision . 2))
                "station,temp\nOslo,12.50\nBergen,\nTromso,4.00\nNarvik,3.50\n")
  (check-equal? (stations-written (select dated-stations "station" "temp")
                                  '(#:float-precision . 2) '(#:quote-style . non-numeric))
                "\"station\",\"temp\"\n\"Oslo\",12.50\n\"Bergen\",\n\"Tromso\",4.00\n\"Narvik\",3.50\n")
  (check-equal? (stations-written (select dated-stations "station" "temp")
                                  '(#:float-scientific . #t))
                "station,temp\nOslo,1.25e1\nBergen,\nTromso,4e0\nNarvik,3.5e0\n")
  (check-equal? (stations-written (select dated-stations "station" "note")
                                  '(#:include-header . #f) '(#:line-terminator . "\r\n")
                                  '(#:quote-style . always))
                "\"Oslo\",\"-\"\r\n\"Bergen\",\"\"\r\n\"Tromso\",\"cold\"\r\n\"Narvik\",\"windy\"\r\n")
  (check-equal? (stations-written (select (read-csv flights #:separator #\tab #:null-values "NA"
                                                    #:try-parse-dates #t #:n-rows 3)
                                          "carrier" "flight" "time_hour")
                                  '(#:batch-size . 1) '(#:datetime-format . "%Y-%m-%dT%H:%M")
                                  '(#:include-bom . #t) '(#:quote-style . non-numeric))
                "﻿\"carrier\",\"flight\",\"time_hour\"\n\"UA\",1545,\"2013-01-01T05:00\"\n\"UA\",1714,\"2013-01-01T05:00\"\n\"AA\",1141,\"2013-01-01T05:00\"\n")
  (check-equal? (rows-of (read-csv flights #:separator #\tab #:null-values "NA"
                                   #:columns '("carrier" "flight" "dep_delay")
                                   #:row-index-name "row" #:n-rows 3))
                '((0 2 "UA" 1545) (1 4 "UA" 1714) (2 2 "AA" 1141)))
  (check-equal? (column-names (read-csv part-1
                                        #:has-header #f #:skip-rows 1
                                        #:new-columns '("from" "to" "delay")))
                '("from" "to" "delay"))

  (check-equal? (rows-of (read-csv flights #:separator #\tab #:null-values "NA"
                                   #:columns '("carrier" "flight" "dep_delay")
                                   #:row-index-name "row" #:row-index-offset 1 #:n-rows 3))
                '((1 2 "UA" 1545) (2 4 "UA" 1714) (3 2 "AA" 1141)))
  (check-equal? (column-names (read-csv flights #:separator #\tab #:columns '(9 10) #:n-rows 2))
                '("carrier" "flight"))
  (check-regexp-match #rx"projection index: 42 is out of bounds for csv schema with length: 19$"
                      (message-of (lambda () (read-csv flights #:separator #\tab
                                                       #:columns '(42)))))
  (check-regexp-match #rx"4 new column names for a file of 3 columns$"
                      (message-of (lambda () (read-csv part-1 #:new-columns '("a" "b" "c" "d")))))
  (check-regexp-match #rx"cannot add row_index with name 'origin'"
                      (message-of (lambda () (read-csv part-1 #:row-index-name "origin"))))
  (check-regexp-match #rx"found more fields than defined in 'Schema'"
                      (message-of (lambda () (read-csv stations #:skip-lines 1
                                                       #:separator #\;))))
  (check-regexp-match #rx"unable to find column \"temperature\""
                      (message-of (lambda () (read-csv stations #:skip-lines 1 #:separator #\;
                                                       #:null-values '(("temperature" . "-"))))))
  (check-equal? (rows-of (read-csv part-1 #:skip-rows-after-header 1)) '(("LGA" "IAH" 4)))
  (check-equal? (~> (read-csv flights #:separator #\tab #:infer-schema #f)
                    (ref #:columns "year")
                    dtype)
                'string)
  (check-equal? (rows-of (~> (scan-csv part-1 #:new-columns '("from" "to") #:row-index-name "row")
                             (frame-filter (gt (col "dep_delay") 3))
                             collect))
                '((1 "LGA" "IAH" 4)))

  (define compressed (build-path data-dir "compressed"))
  (define part-1-frame (read-csv part-1))
  (define zlib-looking (scratch-file csv-dir "zlib-looking.csv" "x^2,y\n1,2\n3,4\n"))
  (define tiny-zlib-looking (scratch-file csv-dir "tiny-zlib-looking.csv" "x^\n1\n"))
  (define bom-first (scratch-file csv-dir "bom-first.csv" "﻿x^2,y\n1,2\n3,4\n"))
  (define (scan-message path)
    (message-of (lambda () (collect (scan-csv path)))))
  (for ([ext '("gz" "zlib" "zst")])
    (define path (build-path compressed (string-append "part-1.csv." ext)))
    (check-true (frame=? (read-csv path) part-1-frame) ext)
    (check-true (frame=? (collect (scan-csv path)) part-1-frame) ext)
    (check-equal? (rows-of (read-csv path #:n-rows 1)) '(("EWR" "IAH" 2)) ext)
    (check-equal? (column-names (read-csv path #:new-columns '("from"))) '("from" "dest" "dep_delay")
                  ext)
    (check-equal? (column-names (collect (scan-csv path #:new-columns '("from"))))
                  '("from" "dest" "dep_delay")
                  ext))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*zlib-looking.csv: .*corrupt deflate stream"
                      (message-of (lambda () (read-csv zlib-looking))))
  (check-regexp-match #rx"corrupt deflate stream" (scan-message zlib-looking))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*tiny-zlib-looking.csv: incomplete deflate stream$"
                      (message-of (lambda () (read-csv tiny-zlib-looking))))
  (check-equal? (rows-of (read-csv bom-first)) '((1 2) (3 4)))
  (check-equal? (column-names (read-csv bom-first)) '("x^2" "y"))
  (check-true (frame=? (read-csv bom-first) (collect (scan-csv bom-first))))

  (check-regexp-match #rx"reads as one column"
                      (message-of (lambda () (read-csv flights #:row-index-name "i"))))
  (check-equal? (shape (read-csv flights #:new-columns '("line"))) '(102 1))
  (define semicolon-name (scratch-file csv-dir "semicolon-name.csv" "a;b,c\n1;2,3\n"))
  (for ([columns '(("a;b") (0))])
    (check-equal? (rows-of (read-csv semicolon-name #:columns columns)) '(("1;2")))
    (check-equal? (column-names (read-csv semicolon-name #:columns columns)) '("a;b")))
  (define semicolons (scratch-file csv-dir "semicolons.csv" "a;b\n1;2\n"))
  (check-regexp-match #rx"reads as one column" (message-of (lambda () (read-csv semicolons))))
  (check-equal? (rows-of (read-csv semicolons #:columns '("a;b"))) '(("1;2")))

  (define (read-message kw value)
    (message-of (lambda () (apply-keywords contracted:read-csv (list (cons kw value)) abc))))
  (for* ([kw '(#:skip-rows #:skip-lines #:skip-rows-after-header #:n-rows #:infer-schema-length)]
         [value (list (add1 size-max) (+ 2 size-max))])
    (check-exn (contract-violation-of 'read-csv)
               (lambda () (apply-keywords contracted:read-csv (list (cons kw value)) abc))
               (format "~a" kw)))
  (check-exn (contract-violation-of 'read-csv)
             (lambda () (contracted:read-csv abc #:columns (list (add1 size-max)))))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: projection index: 18446744073709551615 is out of bounds for csv schema with length: 3$"
                      (read-message '#:columns (list size-max)))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: no data: specified skip_lines is larger than total number of lines\\.$"
                      (read-message '#:skip-lines size-max))
  (check-regexp-match #rx"^read-csv: failed to read csv from [^:]*abc.csv: no data: empty CSV$"
                      (read-message '#:skip-rows size-max))
  (check-equal? (shape (read-csv abc #:skip-rows-after-header size-max)) '(0 3))
  (check-equal? (shape (read-csv abc #:n-rows size-max)) '(3 3))

  (define oracle-source
    (scratch-file csv-dir "write-oracle.csv"
              (string-append
               "i,f,s,d,t,h,b\n"
               "1,1.5,\"a,b\",2024-01-02,2024-01-02 03:04:05.006,05:06:07,true\n"
               ",1e-10,\"q\"\"t\",,,,false\n"
               "3,12345678.9,,2024-12-31,2024-12-31 00:00:00,23:59:59.999999,\n")))
  (define oracle-frame (read-csv oracle-source #:try-parse-dates #t))
  (check-equal? (map second (dtypes-of oracle-frame))
                '(int64 float64 string date (datetime microseconds #f) time boolean))
  (define written-path (build-path csv-dir "written.csv"))
  (define (written kvs)
    (apply-keywords write-csv kvs oracle-frame written-path)
    (file->string written-path))
  (define write-csv-expected (file->value (build-path data-dir "write-csv-expected.rktd")))
  (for ([case (in-list write-csv-expected)])
    (check-equal? (written (car case)) (cadr case) (format "~s" (car case))))
  (check-equal? (written '((#:float-scientific . auto) (#:quote-style . necessary)
                           (#:null-value . "")))
                (written '()))
  (for ([batch-size (list 2 3 4 (expt 2 32) size-max)])
    (check-equal? (written `((#:batch-size . ,batch-size))) (written '()) (format "~a" batch-size)))
  (define precise (written `((#:float-precision . ,float-precision-max))))
  (check-equal? (string-length precise) (+ (string-length (written '((#:float-precision . 0))))
                                           (* 3 (add1 float-precision-max))))
  (for ([kv '((#:datetime-format . "%Q") (#:date-format . "%H") (#:time-format . "%Y"))]
        [cause '("cannot format NaiveDateTime with format '%Q'"
                 "cannot format NaiveDate with format '%H'"
                 "cannot format NaiveTime with format '%Y'")])
    (check-regexp-match (regexp (string-append "^write-csv: failed to write csv to [^:]*written.csv: "
                                               (regexp-quote cause) "$"))
                        (message-of (lambda () (written (list kv))))))
  (check-regexp-match #rx"^write-csv: failed to write csv to [^:]*out.csv: cannot create file: "
                      (message-of (lambda () (write-csv oracle-frame
                                                        (build-path csv-dir "no" "out.csv")))))
  (define round-trip (build-path csv-dir "round-trip.csv"))
  (write-csv station-frame round-trip #:separator #\; #:decimal-comma #t #:null-value "n/a"
             #:quote-style 'always)
  (check-true (frame=? (read-csv round-trip #:separator #\; #:decimal-comma #t
                                 #:null-values "n/a")
                       station-frame))
  (for ([kv `((#:separator . ";") (#:separator . #\newline) (#:quote-char . #\é)
              (#:quote-style . non_numeric) (#:batch-size . 0) (#:float-scientific . yes)
              (#:float-precision . -1) (#:null-value . #f) (#:line-terminator . #\newline)
              (#:datetime-format . sym) (#:include-header . 1) (#:include-bom . "no")
              (#:decimal-comma . 1) (#:batch-size . ,(add1 size-max))
              (#:batch-size . ,(+ 2 size-max)) (#:float-precision . ,(add1 float-precision-max))
              (#:float-precision . ,(add1 size-max)) (#:null-value . "N\u0000A")
              (#:line-terminator . "\r\u0000X") (#:date-format . "%Y\u0000"))])
    (check-exn (contract-violation-of 'write-csv)
               (lambda () (keyword-apply contracted:write-csv (list (car kv)) (list (cdr kv))
                                         (list oracle-frame round-trip)))
               (format "~s" kv)))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:write-csv oracle-frame round-trip
                                              #:separator #\; #:quote-char #\;)))
  (check-exn #rx"quote-char must differ from the separator"
             (lambda () (contracted:write-csv oracle-frame round-trip #:quote-char #\,)))

  (define keep (scratch-file csv-dir "keep.csv" "PRECIOUS"))
  (check-exn #rx"^write-csv: failed to write csv to [^:]*keep.csv: cannot format NaiveDate with format '%H'$"
             (lambda () (write-csv oracle-frame keep #:date-format "%H")))
  (check-equal? (file->string keep) "PRECIOUS")
  (check-equal? (staging-files csv-dir) '())
  (check-staged-write write-csv (lambda (path) (read-csv path #:try-parse-dates #t)) "csv"
                      oracle-frame)

  (define late-float-text
    (string-append "x,s\n"
                   (string-append* (for/list ([i (in-range 150)]) (format "~a,r~a\n" i i)))
                   "1.5,last\n"))
  (define late-float (scratch-file csv-dir "late-float.csv" late-float-text))
  (define parts-dir (build-path data-dir "parts"))
  (define (check-same-as-every label path)
    (define every (read-csv path #:infer-schema-length #f))
    (check-reads-like-every (format "read-csv ~a" label) every
                            (lambda (n) (read-csv path #:infer-schema-length n)))
    (check-reads-like-every (format "scan-csv ~a" label) every
                            (lambda (n) (collect (scan-csv path #:infer-schema-length n)))))
  (for ([(label path) (in-dict (list (cons "late float" late-float)
                                     (cons "one-file glob" (one-file-pattern late-float))
                                     (cons "parts glob" (build-path parts-dir "*.csv"))
                                     (cons "gzip" (build-path compressed "part-1.csv.gz"))
                                     (cons "zlib" (build-path compressed "part-1.csv.zlib"))
                                     (cons "zstd" (build-path compressed "part-1.csv.zst"))))])
    (check-same-as-every label path))
  (check-equal? (dtype (ref (read-csv late-float #:infer-schema-length (expt 2 62)) "x")) 'float64)
  (check-reads-like-every "scan-csv of a directory"
                          (collect (scan-csv parts-dir #:infer-schema-length #f))
                          (lambda (n) (collect (scan-csv parts-dir #:infer-schema-length n))))

  (define late-float-every
    (let ([d (read-csv late-float #:infer-schema-length #f)]) (list (shape d) (dtype (ref d "x")))))
  (define never-reserved (quotient (expt 2 47) 24))
  (define bracketed
    (let ([dir (build-path csv-dir "a[1]")])
      (make-directory dir)
      (scratch-file dir "late-float.csv" late-float-text)
      dir))
  (define (with-memory bytes form)
    `(begin (putenv "POLARS_OVERRIDE_TOTAL_MEMORY" ,bytes) ,form))
  (define unbounded-memory (number->string (sub1 (expt 2 64))))
  (define (scan-before-writing name count)
    (define later (path->string (build-path csv-dir name)))
    `(let ([plan (scan-csv ,later #:infer-schema-length ,count)])
       (call-with-output-file ,later (lambda (out) (write-string ,late-float-text out)))
       (let ([d (collect plan)])
         (write (list (list (shape d) (dtype (ref d "x"))))))))
  (define (read-and-scan path count)
    `(write (for/list ([reader (list (lambda () (read-csv ,path #:infer-schema-length ,count))
                                     (lambda () (collect (scan-csv ,path
                                                                   #:infer-schema-length ,count))))])
              (let ([d (reader)]) (list (shape d) (dtype (ref d "x")))))))
  (for ([child (in-list
                `(("a count no reservation reaches" 1
                   ,(with-memory unbounded-memory
                      (scan-before-writing "unreserved.csv" never-reserved)))
                  ("a count past the host's memory" 1
                   ,(scan-before-writing "past-memory.csv" (sub1 never-reserved)))
                  ("a count past a small file" 2
                   ,(with-memory unbounded-memory
                      (read-and-scan (path->string late-float) (sub1 never-reserved))))
                  ("a count past a small file read from a[1]/" 2
                   ,(with-memory unbounded-memory
                      `(parameterize ([current-directory ,(path->string bracketed)])
                         ,(read-and-scan "late-float.csv" (sub1 never-reserved)))))
                  ("a malformed memory override" 2
                   ,(with-memory "abc" (read-and-scan (path->string late-float) (expt 2 21))))))])
    (match-define (list label reads form) child)
    (define-values (status output errors) (call-in-child form))
    (check-equal? status 0 (format "~a: ~a" label errors))
    (check-equal? errors "" label)
    (check-equal? (read (open-input-string output))
                  (make-list reads late-float-every)
                  label))

  (delete-directory/files csv-dir))
