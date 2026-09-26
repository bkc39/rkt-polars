#lang racket/base

;; Selectors: all, exclude, and col by dtype or regexp.
;;
;; One expression over several columns expands to one output per matched
;; column, each keeping its name:
;;   pl.all()                     ->  (all)
;;   pl.all().exclude("id")       ->  (exclude (all) "id")
;;   pl.col(pl.Float64)           ->  (col 'float64)
;;   pl.col("^.*_high$")          ->  (col "^.*_high$")   ; a Polars regex
;;                                    (col #rx"_high$")    ; a Racket regexp
;; A Racket regexp keeps its Racket meaning.  Polars' regex engine has no
;; lookaround, so a regexp using it fails when the query runs; select those
;; names in Racket with regexp-match? instead.
;;
;; Inside `nix develop`:
;;   racket examples/54-expr-selectors.rkt

(require polars)

(define stocks
  (dataframe
   (list (series '("AAPL" "NVDA" "MSFT") #:name "ticker")
         (series '(229.9 138.93 420.56)  #:name "price")
         (series '(231.31 139.6 424.04)  #:name "day_high")
         (series '(228.6 136.3 417.52)   #:name "day_low")
         (series '(237.23 140.76 468.35) #:name "year_high")
         (series '(164.08 39.23 324.39)  #:name "year_low")
         (series '(51 48 22)             #:name "volume_m" #:dtype 'i32))))

(displayln "input:")
(displayln stocks)

(displayln "every column, then every column but two:")
(displayln (select stocks (all)))
(displayln (select stocks (exclude (all) "ticker" "volume_m")))

(displayln "by dtype: every float64 column, rounded (short and long spellings agree):")
(displayln (select stocks (~> (col 'float64) (round #:decimals 0))))
(displayln (~> stocks (select (col 'f64)) column-names))

(displayln "by a Polars regex string and by a Racket #rx regexp:")
(displayln (select stocks "ticker" (col "^.*_high$")))
(displayln (select stocks "ticker" (col #rx"_(high|low)$")))

(displayln "a #px regexp with Racket's \\w class:")
(displayln (~> stocks (select (col #px"^\\w+_\\w+$")) column-names))

(displayln "exclude by regexp, from a dtype selection:")
(displayln (select stocks (exclude (col 'float64) #rx"^day_")))

(displayln "all inside agg is every column that is not a group key:")
(displayln
 (~> stocks
     (with-columns (~> (col "price") (> 200) (alias "large")))
     (group-by "large")
     (agg (~> (all) (exclude "ticker") mean))
     (sort "large")))

(define lookahead #px"^(?!day_).*_(high|low)$")

(displayln "a lookahead regexp is rejected when the query runs:")
(with-handlers ([exn:fail? (lambda (e) (displayln (exn-message e)))])
  (select stocks (col lookahead)))

(displayln "so match the names in Racket and select them by name:")
(displayln
 (select stocks (filter (lambda (name) (regexp-match? lookahead name))
                        (column-names stocks))))
