# wa_wasi

WASI [preview1](https://github.com/WebAssembly/WASI/blob/main/legacy/preview1/docs.md)
host functions for the Erlang ecosystem — the pure-Erlang core package.

WASI is not a set of new WebAssembly instructions: it is a collection of
standard host-function imports (published under the WASM import-module name
`wasi_snapshot_preview1`) that a WASM module imports and the host implements.
`wa_wasi` supplies those implementations so a compiled WASM module can print
output, read its arguments and environment, get time and randomness, and exit.

## Standalone by design

`wa_wasi` is **standalone**: it depends only on OTP and its own `wa_wasi_*`
modules — it does **not** depend on the [wa_embedder](https://github.com/couchemar/wa_embedder)
WASM→BEAM compiler. Only the user's application depends on both.

Because a compiled host function receives only the WASM integer operands (never
a handle to the module's linear memory), `wa_wasi` defines its own minimal
byte-level memory contract — the `wa_wasi_memory` behaviour — and parameterizes
every host function by a memory accessor and a `wa_wasi_ctx` capabilities
context (stdout/stderr sinks, args, environment, clock source, RNG source). The
user supplies a tiny adapter that bridges the accessor to their runtime's linear
memory.

## Scope

Phase 1 (the "compute and output" slice): `fd_write`, `args_sizes_get` /
`args_get`, `environ_sizes_get` / `environ_get`, `clock_time_get`, `random_get`,
and `proc_exit` (raised as a catchable `{wasi_exit, Code}` — never `halt`).

Filesystem/preopens and WASI preview2 / the Component Model are out of scope for
now (roadmap).

## Elixir

An idiomatic Elixir wrapper, `wa_wasi_ex` (the `WaWasi` module), lives in the
`wa_wasi_ex/` subdirectory and delegates to this core.

## License

Released into the public domain under the [Unlicense](UNLICENSE).
