;; End-to-end proc_exit fixture. Calls proc_exit with a fixed code; the host
;; raises the catchable {wasi_exit, Code} error, which propagates out of this
;; exported function so the test can catch it while the process survives.
(module
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; exit(code) -> (unreachable after the host raises). No result value.
  (func (export "exit") (param i32)
    (call $proc_exit (local.get 0)))
)
