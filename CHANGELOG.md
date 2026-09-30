# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This file covers both packages in the repo: the Erlang core `wa_wasi` and the
Elixir wrapper `wa_wasi_ex`, which are versioned together.

## [Unreleased]

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
