#lang racket/base

;; Lazy join — join two tables and aggregate in one lazy plan, no
;; intermediate .collect().  Mirrors the canonical Polars Python flow:
;;   users.lazy()
;;     .join(orders.lazy(), on="uid", how="inner")
;;     .group_by("name").agg([col("amount").sum().alias("total"),
;;                            col("amount").count().alias("n")])
;;     .sort("total", descending=True)
;;     .collect()
;;
;; Inside `nix develop`:
;;   racket examples/15-lazy-join.rkt

(require polars)

(define users
  (dataframe-new
   (list (series-new-i32 "uid"  '(1 2 3 4))
         (series-new-str "name" '("alice" "bob" "carol" "dan")))))

(define orders
  (dataframe-new
   (list (series-new-i32 "uid"    '(1 1 2 2 2 3))
         (series-new-i32 "amount" '(10 25 30 7 18 4)))))

(displayln "users:")
(display-dataframe users)
(newline)
(displayln "orders:")
(display-dataframe orders)
(newline)

;; One lazy plan: inner join → group_by_agg → sort by total desc.
(define per-user
  (lazyframe-collect
   (lazyframe-sort
    (lazyframe-group-by-agg
     (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                     #:on '("uid") #:how 'inner)
     '("name")
     (list (expr-alias (expr-sum   (col "amount")) "total")
           (expr-alias (expr-count (col "amount")) "n")))
    '("total") #:descending #t)))

(displayln "join(uid).group_by(name).agg(sum,count).sort(total desc):")
(display-dataframe per-user)
(newline)

;; Left join keeps users with no orders (carol's only order is uid=3,
;; dan has none).
(define left-joined
  (lazyframe-collect
   (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders)
                   #:on '("uid") #:how 'left)))

(displayln "left join (keeps unmatched users):")
(display-dataframe left-joined)
(newline)

;; #:left-on / #:right-on for differently named keys.
(define orders-r
  (dataframe-new
   (list (series-new-i32 "buyer"  '(1 2 3))
         (series-new-i32 "amount" '(100 200 300)))))

(define renamed
  (lazyframe-collect
   (lazyframe-join (dataframe-lazy users) (dataframe-lazy orders-r)
                   #:left-on '("uid") #:right-on '("buyer") #:how 'inner)))

(displayln "join with #:left-on=uid #:right-on=buyer:")
(display-dataframe renamed)
