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
  ;; The modules pkg-build's `raco test --drdr` runs, under its stderr rule:
  ;; every module but polars/info.rkt's test-omit-paths, the manual's .scrbl
  ;; and their examples too (no -x), each in its own process, red on any
  ;; write to stderr, a native one included (-e).  Unlike pkg-build: a
  ;; 600 s timeout (its default is 90 s, test-timeouts aside), and no fresh
  ;; PLTUSERHOME, TMPDIR or empty stdin.  The flake's Racket check runs the
  ;; same.
  (test          "raco test -e --timeout 600 -c polars")
  (guide         "raco test -y -e user-guide")
  ;; Every examples/*.rkt, each in its own process; an example is red if it
  ;; raises, exits non-zero or writes to stderr.  The flake's Racket check
  ;; runs it too, with -j 4.
  (examples      "raco test -y -e -Q --empty-stdin -j 8 examples")
  ;; CI's rustfmt check; `nix build .#racket` does not run it.
  (fmt           "cargo fmt --manifest-path rust/Cargo.toml --check")
  ;; A fresh dev shell has no threading docs, and without them the manual's
  ;; `~>` link is an undefined tag, which fails the docs gate, and
  ;; threading-doc looks like an unused dependency.  Cheap once built.
  (threading-doc "raco setup --pkgs threading-doc")
  ;; raco setup over rkt-polars, red on an undefined tag, a key collected
  ;; multiple times or a badlink in the rendered manual, all of which raco
  ;; setup only warns about.  A run that does not render the manual reads the
  ;; warnings its last render recorded.  The flake's Racket build runs the
  ;; same script, and the dev shell's setup on entry records with --record.
  (docs          "scripts/docs-check.sh")
  ;; scripts/docs-check.sh against fixture logs and manuals, with raco,
  ;; racket and tee stubbed.  Plain bash, so no shell.
  (docs-check-test ("bash scripts/docs-check-test.sh" #:shell ""))
  ;; No define-syntax-rule or syntax-rules in the Racket sources.  A grep, so
  ;; no shell.
  (no-syntax-rule ("bash scripts/no-syntax-rule.sh" #:shell ""))
  ;; No test submodule under polars/private: its tests live in the mirrored
  ;; file under polars/tests.  A grep, so no shell.
  (no-inline-tests ("bash scripts/no-inline-tests.sh" #:shell ""))
  ;; No OpenSSL, native-tls or aws-lc in rust/Cargo.lock: HTTPS is rustls on
  ;; ring.  A grep, so no shell.
  (rustls-only   ("bash scripts/rustls-only.sh" #:shell ""))
  ;; No dynamic-wind under polars/private or polars/tests outside
  ;; polars/private/resource.rkt, polars/tests/resource.rkt and the files
  ;; polars/tests/dynamic-wind-sites.rktd names: a scoped resource is paired by
  ;; its with- forms.  A grep, so no shell; the read audit in
  ;; polars/tests/resource.rkt is the per-site check.
  (no-dynamic-wind ("bash scripts/no-dynamic-wind.sh" #:shell ""))
  ;; The four grep gates above on a scratch tree: a hit fails with 1, and a
  ;; missing directory or lock file with 2, never a pass.  Plain bash.
  (grep-gates-test ("bash scripts/grep-gates-test.sh" #:shell ""))
  ;; build-so.sh's darwin branch against a fake rustup (#161).  No shell.
  (build-so      ("bash scripts/test-build-so.sh" #:shell ""))
  ;; Every way into one checkout (a trailing slash, a symlink, a
  ;; subdirectory) keys the dev shell's one PLTUSERHOME.  Plain bash, so no
  ;; shell.
  (devshell-home ("bash scripts/devshell-home-test.sh" #:shell ""))
  ;; The dev shell and copy-native-libs replace libcompat by a rename, never
  ;; in place, so a racket that has it mapped keeps running.  Plain bash.
  (install-native-libs ("bash scripts/install-native-libs-test.sh" #:shell ""))
  ;; scripts/stage-native-package.rkt names the rust/ tree and commit it is
  ;; given or finds recorded, or HEAD's under --head only while rust/ is clean,
  ;; and fails naming why otherwise.  Needs racket and git: the dev shell.
  (stage-native-package "bash scripts/stage-native-package-test.sh")
  ;; scripts/release/ against planted libraries and stubs; needs the dev shell's libcompat.
  (release-gates "bash scripts/release/gates-test.sh polars/native-libs/libcompat.so")
  ;; scripts/test-local.sh copies only the release catalog and
  ;; pkgs.racket-lang.org, the catalogs polars' dependencies come from, so an
  ;; outage elsewhere cannot fail it.  Plain bash, raco stubbed.
  (dependency-catalogs ("bash scripts/dependency-catalogs-test.sh" #:shell ""))
  ;; The project's Resyntax suite (lint/) over the same trees, red on any
  ;; suggestion; `scripts/resyntax-lint.sh fix` applies them.  It takes
  ;; minutes, so it is not a push gate; CI runs it.
  (resyntax      "scripts/resyntax-lint.sh")
  (lint-test     "raco test lint")
  ;; The CI-equivalent: cargo tests, the Racket build with docs, rustfmt, the
  ;; Racket version floor, no-syntax-rule, no-inline-tests, and the release
  ;; rustc pin; not resyntax or lint-test.
  (check         "nix flake check")
  ;; The nycflights scoreboard and ratio table (#86).  Red only when the
  ;; harness itself breaks; a FAIL line or a slow ratio is the arc's to fix.
  (bench         "nix run .#bench")
  ;; The nycflights arc's exit gate (#88, #90): the same run, red on any FAIL
  ;; line or any op over its allowance (bench/allowances.rkt).  Its ratios
  ;; mean something only on a quiet host.
  (bench-strict  "nix run .#bench -- --strict"))
 (push-gates (no-syntax-rule no-inline-tests rustls-only no-dynamic-wind grep-gates-test docs-check-test devshell-home install-native-libs stage-native-package release-gates dependency-catalogs compile test examples fmt)))
