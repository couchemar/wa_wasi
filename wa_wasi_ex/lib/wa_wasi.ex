defmodule WaWasi do
  @moduledoc """
  Idiomatic Elixir facade over the pure-Erlang `:wa_wasi` core.

  WASI preview1 host functions for running WebAssembly modules on the BEAM.
  This wrapper delegates to `:wa_wasi`, `:wa_wasi_ctx`, and `:wa_wasi_preview1`;
  only plain terms (lists/tuples/maps/atoms/integers/binaries) cross the
  Elixir↔Erlang boundary — never Elixir structs.

  The public API (import-map builder, context constructor, host-function
  passthroughs) is implemented in a later task.
  """
end
