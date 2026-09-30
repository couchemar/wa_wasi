;; End-to-end clock fixture. Calls clock_time_get for realtime (id 0) and
;; monotonic (id 1) into memory, so the test can assert the fixed 8-byte
;; little-endian timestamps written by the host against a {fixed, Rt, Mono}
;; clock. Note the WASI ABI types clock_time_get's precision as i64.
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))

  (memory (export "memory") 1)

  ;; realtime() -> errno. clock_id=0, precision=0, time_ptr=0 (writes 8 bytes).
  (func (export "realtime") (result i32)
    (call $clock_time_get (i32.const 0) (i64.const 0) (i32.const 0)))

  ;; monotonic() -> errno. clock_id=1, precision=0, time_ptr=8.
  (func (export "monotonic") (result i32)
    (call $clock_time_get (i32.const 1) (i64.const 0) (i32.const 8)))

  ;; read back a 64-bit little-endian value the host wrote.
  (func (export "read64") (param i32) (result i64)
    (i64.load (local.get 0)))
)
