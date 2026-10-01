;; End-to-end sched_yield fixture. Calls sched_yield (a no-op scheduler yield
;; that touches no memory and needs no capability) and returns the errno, so
;; the test can assert ESUCCESS (0).
(module
  (import "wasi_snapshot_preview1" "sched_yield"
    (func $sched_yield (result i32)))

  (memory (export "memory") 1)

  ;; run() -> errno. Just forwards the host's result.
  (func (export "run") (result i32)
    (call $sched_yield))
)
