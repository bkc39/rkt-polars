#lang racket/base

;; DataFrame joins + vstack, prefix-free and data-first, so they thread:
;;   left.join(right, on=..., how=...)  ->  (~> left (join right #:on ... #:how ...))
;;   df.vstack(other)                   ->  (~> df (vstack other))
;;
;; Inside `nix develop`:
;;   racket examples/10-dataframe-joins.rkt

(require polars)

(define users
  (dataframe (list (series '(1 2 3 4) #:name "uid" #:dtype 'i32)
                   (series '("alice" "bob" "carol" "dora") #:name "name"))))

(define orders
  (dataframe (list (series '(1 2 2 5) #:name "uid" #:dtype 'i32)
                   (series '(10 20 30 40) #:name "amount" #:dtype 'i32))))

(displayln "users:")
(displayln users)
(newline)

(displayln "orders:")
(displayln orders)
(newline)

(displayln "inner join on uid:")
(displayln (~> users (join orders #:on '("uid") #:how 'inner)))
(newline)

(displayln "left join on uid:")
(displayln (~> users (join orders #:on '("uid") #:how 'left)))
(newline)

(displayln "outer join on uid:")
(displayln (~> users (join orders #:on '("uid") #:how 'outer)))
(newline)

;; Cross join — Cartesian product, no key.  Restrict to small slices.
(displayln "cross join (head 2 x head 2):")
(displayln (~> (head users 2) (join (head orders 2) #:how 'cross)))
(newline)

;; vstack — append rows from another (compatible) dataframe
(define more-users
  (dataframe (list (series '(5 6) #:name "uid" #:dtype 'i32)
                   (series '("eve" "frank") #:name "name"))))

(displayln "vstack(users, more-users):")
(displayln (~> users (vstack more-users)))
