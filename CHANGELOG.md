# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file covers both packages in the repo: the Erlang core `wa_wasi` and the
Elixir wrapper `wa_wasi_ex`, which are versioned together.

## [Unreleased]

### Added

- Non-filesystem preview1 completion — four new `wasi_snapshot_preview1` host
  functions: `clock_res_get` (reports a clock's resolution; realtime id 0 /
  monotonic id 1, unknown ids return `EINVAL`), `sched_yield` (a no-op
  scheduler yield that always succeeds), `fd_fdstat_get` (writes the 24-byte
  fdstat struct for the standard fds — `character_device` with the `fd_write`
  right for fd 1/2 and the `fd_read` right for a configured fd 0), and `fd_read`
  (the read counterpart of `fd_write`, filling iovec buffers from a configured
  stdin source on fd 0 and writing the total bytes read).
- Two new `wa_wasi_ctx` capabilities, each defaulting to absent (no ambient host
  read): a Stdin_Source (`:stdin` — `{fixed, Bytes}` / `{fun, F}`) supplying the
  bytes readable on fd 0, and a Clock_Resolution_Source (`:clock_res` —
  `{fixed, RtNs, MonoNs}` / `{fun, F}`) supplying per-clock resolutions, with
  shape validation and `require_stdin/1` / `require_clock_res/1` resolvers.
- `encode_u16/1` little-endian codec helper and named Fdstat/Rights/Filetype
  constants (no new Errno beyond the existing four).
- `WaWasi` Elixir passthroughs for the four new functions (`clock_res_get/4`,
  `sched_yield/1`, `fd_fdstat_get/4`, `fd_read/6`); `context/1` now accepts the
  `:stdin` and `:clock_res` keys.

## [0.1.0] - 2026-09-30

### Added

- Initial release: WASI preview1 host functions (the `wasi_snapshot_preview1`
  import module) as a standalone, pure-Erlang library, plus the thin Elixir
  wrapper `WaWasi`. The core has no Elixir dependency and drops into a WASM
  runtime's import map without depending on `wa_embedder`.
- Phase 1 host functions: `fd_write` (iovecs to a configured stdout/stderr
  sink), `args_sizes_get` / `args_get`, `environ_sizes_get` / `environ_get`,
  `clock_time_get` (realtime id 0 / monotonic id 1; unknown ids return
  `EINVAL`), `random_get`, and `proc_exit` (raises a catchable
  `{wasi_exit, Code}`, never halts the BEAM).
- `Wa_Wasi_Memory` behaviour (`read_bytes/3`, `write_bytes/3`) with bounded
  `read/3` and `write/3` helpers, so host functions read and write a WASM
  module's linear memory through a `{module, handle}` accessor the caller
  supplies — without the core depending on any specific memory backend.
- `wa_wasi_ctx` capabilities/configuration context: stdout/stderr sinks, args,
  environment, and pluggable clock and RNG sources (including deterministic
  `{fixed, ...}` sources and opt-in `host_clock/0` / `crypto_rng/0` helpers).
- `WaWasi` Elixir wrapper: `imports/2`, `context/1`, and direct host-function
  passthroughs, delegating to the Erlang core with only plain terms crossing the
  boundary.
- Little-endian codec (`encode_u32`/`decode_u32`/`encode_u64`/`decode_iovecs`)
  and named errno constants. Out-of-bounds memory access fails atomically with
  `EFAULT`, leaving memory unmodified.

[Unreleased]: https://github.com/couchemar/wa_wasi
[0.1.0]: https://github.com/couchemar/wa_wasi
