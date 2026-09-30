(module
  ;; End-to-end fd_write fixture. Imports wasi_snapshot_preview1.fd_write and
  ;; writes a fixed string to fd 1 (stdout) via two iovecs, so the test can
  ;; assert the collected sink bytes and the returned errno + nwritten value.
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; Memory layout (via data segments):
  ;;   [0]  iovec 0: buf_ptr=32 (u32 LE), buf_len=6
  ;;   [8]  iovec 1: buf_ptr=38 (u32 LE), buf_len=7
  ;;   [16] nwritten slot (4 bytes)
  ;;   [32] "Hello," (6 bytes)
  ;;   [38] " WASI!\n" (7 bytes)  -- total 13 bytes
  (data (i32.const 0) "\20\00\00\00\06\00\00\00")   ;; iovec0 {32, 6}
  (data (i32.const 8) "\26\00\00\00\07\00\00\00")   ;; iovec1 {38, 7}
  (data (i32.const 32) "Hello,")
  (data (i32.const 38) " WASI!\n")

  ;; run() -> errno. fd=1, iovs_ptr=0, iovs_len=2, nwritten_ptr=16.
  (func (export "run") (result i32)
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 2) (i32.const 16)))

  ;; read back the nwritten count the host wrote at offset 16.
  (func (export "nwritten") (result i32)
    (i32.load (i32.const 16)))
)
