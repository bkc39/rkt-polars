#lang racket/base

;; DataFrame joins + vstack (DF Phase 5).
;;
;; Inside `nix develop`:
;;   racket examples/10-dataframe-joins.rkt

(require polars)

(define users
  (dataframe-new
   (list (series-new-i32 "uid"  '(1 2 3 4))
         (series-new-str "name" '("alice" "bob" "carol" "dora")))))

(define orders
  (dataframe-new
   (list (series-new-i32 "uid"    '(1 2 2 5))
         (series-new-i32 "amount" '(10 20 30 40)))))

(displayln "users:")
(display-dataframe users)
(newline)

(displayln "orders:")
(display-dataframe orders)
(newline)

(displayln "inner join on uid:")
(display-dataframe (dataframe-join users orders #:on '("uid") #:how 'inner))
(newline)

(displayln "left join on uid:")
(display-dataframe (dataframe-join users orders #:on '("uid") #:how 'left))
(newline)

(displayln "outer join on uid:")
(display-dataframe (dataframe-join users orders #:on '("uid") #:how 'outer))
(newline)

;; Cross join — Cartesian product, no key.  Restrict to small slices
;; so the output stays readable.
(define small-users (dataframe-head users 2))
(define small-orders (dataframe-head orders 2))
(displayln "cross join (head 2 x head 2):")
(display-dataframe (dataframe-join small-users small-orders #:how 'cross))
(newline)

;; vstack — append rows from another (compatible) dataframe
(define more-users
  (dataframe-new
   (list (series-new-i32 "uid"  '(5 6))
         (series-new-str "name" '("eve" "frank")))))

(displayln "vstack(users, more-users):")
(display-dataframe (dataframe-vstack users more-users))
