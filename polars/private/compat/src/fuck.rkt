#lang racket

(require racket/system)

(define (run-cargo-build)
  (define cmd "cargo build --manifest-path=compat/Cargo.toml --release")
  (define result (system cmd))
  (cond
    [(eq? result 0)
     (displayln "Build successful!")]
    [else
     (displayln "Build failed!")])
  result)


(module+ main
  (run-cargo-build))
