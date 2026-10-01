;; End-to-end fd_fdstat_get fixture. Writes the 24-byte fdstat struct for
;; fd 1 (stdout) and fd 0 (stdin, with a Stdin_Source configured) into memory,
;; so the test can assert the filetype / flags / rights fields the host wrote.
;;
;; Fdstat layout (24 bytes, 8-byte aligned):
;;   fs_filetype        u8  @0
;;   (pad)              u8  @1
;;   fs_flags           u16 @2 (LE)
;;   (pad)              u32 @4..7
;;   fs_rights_base     u64 @8  (LE)
;;   fs_rights_inheriting u64 @16 (LE)
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    (func $fd_fdstat_get (param i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; stdout() -> errno. fd=1, buf_ptr=0 (writes 24 bytes at offset 0).
  (func (export "stdout") (result i32)
    (call $fd_fdstat_get (i32.const 1) (i32.const 0)))

  ;; stdin() -> errno. fd=0, buf_ptr=32 (writes 24 bytes at offset 32).
  (func (export "stdin") (result i32)
    (call $fd_fdstat_get (i32.const 0) (i32.const 32)))

  ;; read back an 8-bit value the host wrote (filetype, padding).
  (func (export "read8") (param i32) (result i32)
    (i32.load8_u (local.get 0)))

  ;; read back a 16-bit little-endian value (fs_flags).
  (func (export "read16") (param i32) (result i32)
    (i32.load16_u (local.get 0)))

  ;; read back a 64-bit little-endian value (rights fields).
  (func (export "read64") (param i32) (result i64)
    (i64.load (local.get 0)))
)
