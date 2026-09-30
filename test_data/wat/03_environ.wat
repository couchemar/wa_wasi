(module
  ;; End-to-end environ fixture. Mirrors 02_args.wat for environ_sizes_get /
  ;; environ_get, so the test can assert count, buffer size, and the
  ;; NUL-terminated KEY=VALUE strings against a known env config.
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get"
    (func $environ_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; sizes() -> errno. Writes count at [0], buf_size at [4].
  (func (export "sizes") (result i32)
    (call $environ_sizes_get (i32.const 0) (i32.const 4)))

  ;; get() -> errno. Pointer array at [64], string buffer at [128].
  (func (export "get") (result i32)
    (call $environ_get (i32.const 64) (i32.const 128)))

  (func (export "read32") (param i32) (result i32)
    (i32.load (local.get 0)))
  (func (export "read8") (param i32) (result i32)
    (i32.load8_u (local.get 0)))
)
