;; End-to-end random fixture. Calls random_get to fill a buffer, so the test
;; can assert the exact bytes written by a {fixed, Bytes} rng source (which
;; cycles/truncates the seed to the requested length).
(module
  (import "wasi_snapshot_preview1" "random_get"
    (func $random_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; fill(len) -> errno. Writes `len` bytes at buffer offset 0.
  (func (export "fill") (param i32) (result i32)
    (call $random_get (i32.const 0) (local.get 0)))

  ;; read back a single byte.
  (func (export "read8") (param i32) (result i32)
    (i32.load8_u (local.get 0)))
)
