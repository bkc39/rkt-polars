#lang racket/base

(require racket/runtime-path)

(provide native-libs-dir)

(define-runtime-path native-libs-dir "native-libs")
