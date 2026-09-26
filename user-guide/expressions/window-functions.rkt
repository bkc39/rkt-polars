#lang racket/base

;; rkt-polars user guide — Expressions: Window functions
;; Mirrors https://docs.pola.rs/user-guide/expressions/window-functions/
;; and window_functions.py.
;;
;; Inside `nix develop`:
;;   racket user-guide/expressions/window-functions.rkt

(require polars)

;; The first rows of upstream's Pokémon table.
;; API gap: no Enum dtype, so the types stay strings.
(define pokemon
  (dataframe
   (list (series '("Bulbasaur" "Ivysaur" "Venusaur" "Charmander" "Charmeleon"
                   "Charizard" "Mega Charizard X" "Squirtle"
                   "Wartortle" "Blastoise")
                 #:name "Name")
         (series '("Grass" "Grass" "Grass" "Fire" "Fire" "Fire" "Fire"
                   "Water" "Water" "Water")
                 #:name "Type 1")
         (series (list "Poison" "Poison" "Poison" polars-null polars-null
                       "Flying" "Dragon" polars-null polars-null polars-null)
                 #:name "Type 2")
         (series '(49 62 82 52 64 84 130 48 63 83) #:name "Attack")
         (series '(45 60 80 65 80 100 100 43 58 78) #:name "Speed"))))

(displayln pokemon)

;; --- operations per group ------------------------------------------------
(displayln
 (select pokemon
         "Name" "Type 1"
         (~> (col "Speed")
             (rank #:method 'dense #:descending #t)
             (over "Type 1")
             (alias "Speed rank"))))

(displayln
 (select pokemon
         "Name" "Type 1" "Type 2"
         (~> (col "Speed")
             (rank #:method 'dense #:descending #t)
             (over "Type 1" "Type 2")
             (alias "Speed rank"))))

;; --- mapping results to dataframe rows -----------------------------------
;; API gap: over has no mapping_strategy; it always maps as group_to_rows.
(define athletes
  (dataframe (list (series '("A" "B" "C" "D" "E" "F") #:name "athlete")
                   (series '("PT" "NL" "NL" "PT" "PT" "NL") #:name "country")
                   (series '(6 1 5 4 2 3) #:name "rank"))))

(displayln athletes)

;; group_to_rows; a regexp col stands in for pl.col("athlete", "rank").
(displayln
 (select athletes
         (~> (col #rx"^(athlete|rank)$")
             (sort-by #:by (col "rank"))
             (over (col "country")))
         (col "country")))

;; explode: sort the frame instead (groups come in key order).
(displayln (sort athletes '("country" "rank")))

;; join: collect each group's values with agg and join them back.
(displayln
 (join (drop athletes "rank")
       (~> athletes (group-by "country") (agg (sort-by (col "rank") #:by "rank")))
       #:on '("country")
       #:how 'left))

;; --- windowed aggregation expressions ------------------------------------
(displayln
 (select pokemon
         "Name" "Type 1" "Speed"
         (~> (col "Speed") mean (over (col "Type 1")) (alias "Mean speed in group"))))

;; --- more examples -------------------------------------------------------
;; API gap: no explode, so rank within the window and filter for the rows;
;; the strongest and alphabetical first three follow the same pattern.
(displayln
 (~> pokemon
     (with-columns (~> (col "Speed")
                       (rank #:method 'ordinal #:descending #t)
                       (over "Type 1")
                       (alias "fastest/group")))
     (filter (<= (col "fastest/group") 3))
     (select "Type 1" "Name" "fastest/group")
     (sort '("Type 1" "fastest/group"))))
