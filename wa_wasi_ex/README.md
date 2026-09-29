# WaWasiEx

Idiomatic Elixir wrapper over the [`wa_wasi`](../README.md) WASI preview1
host-function library (the Erlang `:wa_wasi` core).

`WaWasi` builds a `wasi_snapshot_preview1` import map for a memory accessor and
a capabilities context (stdout/stderr sinks, args, environment, clock, RNG),
ready to merge into a WASM runtime's import map. Every function delegates to the
`:wa_wasi` core; only plain terms cross the Elixir↔Erlang boundary.

## Dependencies

- **Core:** the `:wa_wasi` Erlang package. For local development set
  `WA_WASI_PATH=..` (the Nix dev shell does this) to build against the sibling
  source; otherwise the published `{:wa_wasi, "~> 0.1"}` hex release is used.
- **Test-only:** `wa_embedder_ex` (`only: :test`) — the end-to-end tests compile
  and run real WASM modules through it to exercise the WASI host functions. It
  is excluded from the shipped package; neither `wa_wasi` nor `wa_wasi_ex`
  depends on `wa_embedder`/`wa_embedder_ex` at runtime.

## License

Released into the public domain under the [Unlicense](UNLICENSE).
