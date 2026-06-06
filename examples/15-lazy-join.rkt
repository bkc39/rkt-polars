#lang racket/base

;; Lazy join — join two tables and aggregate in one lazy plan, no intermediate
;; collect.  Mirrors:
;;   users.lazy().join(orders.lazy(), on="uid", how="inner")
;;     .group_by("name").agg(col("amount").sum().alias("total"),
;;                           col("amount").count().alias("n"))
;;     .sort("total", descending=True).collect()
;;
;; Inside `nix develop`:
;;   racket examples/15-lazy-join.rkt

(require polars)

(define users
  (dataframe (list (series '(1 2 3 4) #:name "uid" #:dtype 'i32)
                   (series '("alice" "bob" "carol" "dan") #:name "name"))))

(define orders
  (dataframe (list (series '(1 1 2 2 2 3)   #:name "uid" #:dtype 'i32)
                   (series '(10 25 30 7 18 4) #:name "amount" #:dtype 'i32))))

(displayln "users:")
(displayln users)
(newline)
(displayln "orders:")
(displayln orders)
(newline)

;; One lazy plan: inner join -> group-by/agg -> sort by total desc.
(displayln "join(uid).group_by(name).agg(sum,count).sort(total desc):")
(displayln (~> users
               lazy
               (join (lazy orders) #:on '("uid") #:how 'inner)
               (group-by "name")
               (agg (~> (col "amount") sum   (alias "total"))
                    (~> (col "amount") count (alias "n")))
               (sort "total" #:descending #t)
               collect))
(newline)

;; Left join keeps users with no matching orders (dan).
(displayln "left join (keeps unmatched users):")
(displayln (~> users lazy (join (lazy orders) #:on '("uid") #:how 'left) collect))
(newline)

;; #:left-on / #:right-on for differently named keys.
(define orders-r
  (dataframe (list (series '(1 2 3)       #:name "buyer" #:dtype 'i32)
                   (series '(100 200 300) #:name "amount" #:dtype 'i32))))

(displayln "join with #:left-on=uid #:right-on=buyer:")
(displayln (~> users lazy (join (lazy orders-r) #:left-on '("uid") #:right-on '("buyer") #:how 'inner) collect))
