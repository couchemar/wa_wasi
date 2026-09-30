(module
  ;; End-to-end args fixture. Calls args_sizes_get then args_get into memory and
  ;; exports readers so the test can assert the count, buffer size, the pointer
  ;; array, and the NUL-terminated arg strings against a known args config.
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get"
    (func $args_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; sizes() -> errno. Writes argc at [0], argv_buf_size at [4].
  (func (export "sizes") (result i32)
    (call $args_sizes_get (i32.const 0) (i32.const 4)))

  ;; get() -> errno. Pointer array at [64], string buffer at [128].
  (func (export "get") (result i32)
    (call $args_get (i32.const 64) (i32.const 128)))

  ;; readers
  (func (export "read32") (param i32) (result i32)
    (i32.load (local.get 0)))
  (func (export "read8") (param i32) (result i32)
    (i32.load8_u (local.get 0)))
)
