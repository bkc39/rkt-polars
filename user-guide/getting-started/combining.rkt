#lang racket/base

;; rkt-polars user guide — Combining DataFrames
;; Mirrors https://docs.pola.rs/user-guide/getting-started/ (the "Combining
;; dataframes" section: join and concat) and combining.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/getting-started/combining.rkt

(require polars)

(define users
  (dataframe-new
   (list (series '(1 2 3 4) #:name "uid" #:dtype 'i32)
         (series '("alice" "bob" "carol" "dan") #:name "name"))))

(define orders
  (dataframe-new
   (list (series '(1 1 2 3) #:name "uid" #:dtype 'i32)
         (series '(10 25 30 7) #:name "amount" #:dtype 'i32))))

(displayln "users:")
(display-dataframe users)
(newline)
(displayln "orders:")
(display-dataframe orders)
(newline)

;; --- join ---------------------------------------------------------------
;; Inner join on uid, then aggregate per user, in one lazy plan.
(displayln "inner join(uid).group_by(name).agg(total, n).sort(total desc):")
(display-dataframe
 (lazyframe-collect
  (lazyframe-sort
   (lazyframe-group-by-agg
    (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                    #:on '("uid") #:how 'inner)
    '("name")
    (list (expr-alias (expr-sum   (col "amount")) "total")
          (expr-alias (expr-count (col "amount")) "n")))
   '("total") #:descending #t)))
(newline)

;; A left join keeps users with no matching orders (dan has none).
(displayln "left join (keeps unmatched users):")
(display-dataframe
 (lazyframe-collect
  (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                  #:on '("uid") #:how 'left)))
(newline)

;; --- concat -------------------------------------------------------------
;; Vertical concatenation stacks rows of two frames with the same schema.
(define more-users
  (dataframe-new
   (list (series '(5 6) #:name "uid" #:dtype 'i32)
         (series '("erin" "frank") #:name "name"))))

(displayln "vertical concat (users ++ more-users):")
(display-dataframe (dataframe-vstack users more-users))
