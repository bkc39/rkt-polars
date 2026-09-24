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
  (guide         "raco test user-guide")
  ;; CI's rustfmt check; `nix build .#racket` does not run it.
  (fmt           "cargo fmt --manifest-path rust/Cargo.toml --all --check")
  ;; A fresh dev shell has no threading docs, and without them the manual's
  ;; `~>` link is an undefined tag and threading-doc looks like an unused
  ;; dependency.  Cheap once built.
  (threading-doc "raco setup --pkgs threading-doc")
  (docs          "raco setup --check-pkg-deps --unused-pkg-deps --pkgs rkt-polars")
  ;; The CI-equivalent: cargo tests, the Racket build with docs, rustfmt, and
  ;; the Racket version floor.
  (check         "nix flake check"))
 (push-gates (compile test fmt)))
