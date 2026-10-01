;; End-to-end fd_read fixture. Sets up two iovecs pointing at buffers in
;; memory, calls fd_read on fd 0 (stdin), and exports readers for the filled
;; buffer bytes and the nread slot, so the test can assert the bytes pulled
;; from a {fixed, Bytes} Stdin_Source and the total count written.
;;
;; Memory layout (via data segments):
;;   [0]  iovec 0: buf_ptr=32 (u32 LE), buf_len=4
;;   [8]  iovec 1: buf_ptr=40 (u32 LE), buf_len=4
;;   [16] nread slot (4 bytes)
;;   [32] buffer 0 (4 bytes, zero-filled)
;;   [40] buffer 1 (4 bytes, zero-filled)
(module
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 0) "\20\00\00\00\04\00\00\00")   ;; iovec0 {32, 4}
  (data (i32.const 8) "\28\00\00\00\04\00\00\00")   ;; iovec1 {40, 4}

  ;; run() -> errno. fd=0, iovs_ptr=0, iovs_len=2, nread_ptr=16.
  (func (export "run") (result i32)
    (call $fd_read (i32.const 0) (i32.const 0) (i32.const 2) (i32.const 16)))

  ;; read back the nread count the host wrote at offset 16.
  (func (export "nread") (result i32)
    (i32.load (i32.const 16)))

  ;; read back an 8-bit value from a filled buffer.
  (func (export "read8") (param i32) (result i32)
    (i32.load8_u (local.get 0)))
)
