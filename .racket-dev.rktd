;; Gates for the racket-dev plugin's runner (hooks/gate.rkt) and pre-push hook.
;;
;;   racket <plugin>/hooks/gate.rkt . all      ; everything, in this order
;;   racket <plugin>/hooks/gate.rkt . push     ; the subset the pre-push hook runs
;;   racket <plugin>/hooks/gate.rkt . docs     ; one gate by name
;;
;; A command whose first word is `nix` runs as is; every other command is
;; prefixed by `shell`.  nix reads the git-tracked tree, so stage new files
;; before any nix gate.

((shell "nix develop --command")
 (base-ref "origin/master")
 (gates
  ;; Rebuild libcompat from rust/ and stage it; required after any Rust change,
  ;; otherwise the Racket tests run against the stale library.
  (native        "nix run .#copy-native-libs")
  (compile       "raco make polars/main.rkt")
  (test          "raco test -x -c polars")
  (guide         "raco test -y user-guide")
  ;; Every examples/*.rkt, each in its own process; an example is red if it
  ;; raises, exits non-zero or writes to stderr.  The flake's Racket check
  ;; runs it too, with -j 4.
  (examples      "raco test -y -e -Q --empty-stdin -j 8 examples")
  ;; CI's rustfmt check; `nix build .#racket` does not run it.
  (fmt           "cargo fmt --manifest-path rust/Cargo.toml --all --check")
  ;; A fresh dev shell has no threading docs, and without them the manual's
  ;; `~>` link is an undefined tag and threading-doc looks like an unused
  ;; dependency.  Cheap once built.
  (threading-doc "raco setup --pkgs threading-doc")
  (docs          "raco setup --check-pkg-deps --unused-pkg-deps --pkgs rkt-polars")
  ;; No define-syntax-rule or syntax-rules in the Racket sources.  A grep, so
  ;; no shell.
  (no-syntax-rule ("bash scripts/no-syntax-rule.sh" #:shell ""))
  ;; The project's Resyntax suite (lint/) over the same trees, red on any
  ;; suggestion; `scripts/resyntax-lint.sh fix` applies them.  It takes
  ;; minutes, so it is not a push gate; CI runs it.
  (resyntax      "scripts/resyntax-lint.sh")
  (lint-test     "raco test lint")
  ;; The CI-equivalent: cargo tests, the Racket build with docs, rustfmt, the
  ;; Racket version floor, no-syntax-rule, and the release rustc pin; not
  ;; resyntax or lint-test.
  (check         "nix flake check")
  ;; The nycflights scoreboard and ratio table (#86).  Red only when the
  ;; harness itself breaks; a FAIL line or a slow ratio is the arc's to fix.
  (bench         "nix run .#bench")
  ;; The nycflights arc's exit gate (#88, #90): the same run, red on any FAIL
  ;; line or any op over its allowance (bench/allowances.rkt).  Its ratios
  ;; mean something only on a quiet host.
  (bench-strict  "nix run .#bench -- --strict"))
 (push-gates (no-syntax-rule compile test examples fmt)))
