;; End-to-end clock_res_get fixture. Calls clock_res_get for realtime (id 0)
;; and monotonic (id 1) into memory, so the test can assert the fixed 8-byte
;; little-endian resolutions written by the host against a {fixed, Rt, Mono}
;; Clock_Resolution_Source.
(module
  (import "wasi_snapshot_preview1" "clock_res_get"
    (func $clock_res_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; realtime() -> errno. clock_id=0, res_ptr=0 (writes 8 bytes).
  (func (export "realtime") (result i32)
    (call $clock_res_get (i32.const 0) (i32.const 0)))

  ;; monotonic() -> errno. clock_id=1, res_ptr=8.
  (func (export "monotonic") (result i32)
    (call $clock_res_get (i32.const 1) (i32.const 8)))

  ;; read back a 64-bit little-endian value the host wrote.
  (func (export "read64") (param i32) (result i64)
    (i64.load (local.get 0)))
)
