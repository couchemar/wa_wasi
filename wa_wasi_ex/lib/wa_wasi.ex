defmodule WaWasi do
  @moduledoc """
  Idiomatic Elixir facade over the pure-Erlang `:wa_wasi` core.

  WASI preview1 host functions for running WebAssembly modules on the BEAM.
  Build a `wasi_snapshot_preview1` import map for a memory accessor and a
  capabilities context, then merge it into your WASM runtime's import map.

  Every function delegates to `:wa_wasi`, `:wa_wasi_ctx`, or `:wa_wasi_preview1`.
  Only plain terms (lists/tuples/maps/atoms/integers/binaries) cross the
  Elixir↔Erlang boundary — never Elixir structs.

  ## Types

    * accessor — `{module, handle}` where `module` implements the
      `:wa_wasi_memory` behaviour (`read_bytes/3`, `write_bytes/3`).
    * ctx — an opaque `:wa_wasi_ctx` value built with `context/1`.

  ## Example

      ctx = WaWasi.context(%{stdout: :collect, args: [<<"prog">>]})
      imports = WaWasi.imports({MyMemory, handle}, ctx)
      # merge `imports` into the WASM runtime's import map
  """

  @type accessor :: {module(), term()}
  @type ctx :: :wa_wasi_ctx.t()

  @doc """
  Build the `wasi_snapshot_preview1` import map for an `accessor` and `ctx`.

  Returns `%{binary => %{binary => fun}}` with one arity-exact closure per WASI
  preview1 function, ready to merge into a WASM runtime's import map.
  """
  @spec imports(accessor(), ctx()) :: %{binary() => %{binary() => fun()}}
  def imports(accessor, ctx), do: :wa_wasi.imports(accessor, ctx)

  @doc """
  Construct a capabilities/configuration context from a plain options map.

  Recognized keys: `:stdout`, `:stderr` (a sink), `:args` (list of binaries),
  `:env` (list of `{key, value}` binaries), `:clock`, `:rng`, `:stdin`,
  `:clock_res`. Missing sinks/clock/rng/stdin/clock_res default to absent;
  `:args`/`:env` default to `[]`.
  """
  @spec context(map()) :: ctx()
  def context(opts) when is_map(opts), do: :wa_wasi_ctx.new(opts)

  # --- Direct host-function passthroughs (plain terms only) ---

  @doc "See `:wa_wasi_preview1.fd_write/6`."
  @spec fd_write(accessor(), ctx(), integer(), integer(), integer(), integer()) :: integer()
  def fd_write(accessor, ctx, fd, iovs_ptr, iovs_len, nwritten_ptr) do
    :wa_wasi_preview1.fd_write(accessor, ctx, fd, iovs_ptr, iovs_len, nwritten_ptr)
  end

  @doc "See `:wa_wasi_preview1.args_sizes_get/4`."
  @spec args_sizes_get(accessor(), ctx(), integer(), integer()) :: integer()
  def args_sizes_get(accessor, ctx, count_ptr, buf_size_ptr) do
    :wa_wasi_preview1.args_sizes_get(accessor, ctx, count_ptr, buf_size_ptr)
  end

  @doc "See `:wa_wasi_preview1.args_get/4`."
  @spec args_get(accessor(), ctx(), integer(), integer()) :: integer()
  def args_get(accessor, ctx, ptr_array_ptr, buf_ptr) do
    :wa_wasi_preview1.args_get(accessor, ctx, ptr_array_ptr, buf_ptr)
  end

  @doc "See `:wa_wasi_preview1.environ_sizes_get/4`."
  @spec environ_sizes_get(accessor(), ctx(), integer(), integer()) :: integer()
  def environ_sizes_get(accessor, ctx, count_ptr, buf_size_ptr) do
    :wa_wasi_preview1.environ_sizes_get(accessor, ctx, count_ptr, buf_size_ptr)
  end

  @doc "See `:wa_wasi_preview1.environ_get/4`."
  @spec environ_get(accessor(), ctx(), integer(), integer()) :: integer()
  def environ_get(accessor, ctx, ptr_array_ptr, buf_ptr) do
    :wa_wasi_preview1.environ_get(accessor, ctx, ptr_array_ptr, buf_ptr)
  end

  @doc "See `:wa_wasi_preview1.clock_time_get/5`."
  @spec clock_time_get(accessor(), ctx(), integer(), integer(), integer()) :: integer()
  def clock_time_get(accessor, ctx, clock_id, precision, time_ptr) do
    :wa_wasi_preview1.clock_time_get(accessor, ctx, clock_id, precision, time_ptr)
  end

  @doc "See `:wa_wasi_preview1.random_get/4`."
  @spec random_get(accessor(), ctx(), integer(), integer()) :: integer()
  def random_get(accessor, ctx, buf_ptr, buf_len) do
    :wa_wasi_preview1.random_get(accessor, ctx, buf_ptr, buf_len)
  end

  @doc """
  See `:wa_wasi_preview1.proc_exit/2`. Raises the catchable Erlang error
  `{:wasi_exit, code}` — never returns and never halts the BEAM.
  """
  @spec proc_exit(ctx(), integer()) :: no_return()
  def proc_exit(ctx, code), do: :wa_wasi_preview1.proc_exit(ctx, code)

  @doc "See `:wa_wasi_preview1.clock_res_get/4`."
  @spec clock_res_get(accessor(), ctx(), integer(), integer()) :: integer()
  def clock_res_get(accessor, ctx, clock_id, res_ptr) do
    :wa_wasi_preview1.clock_res_get(accessor, ctx, clock_id, res_ptr)
  end

  @doc "See `:wa_wasi_preview1.sched_yield/1`."
  @spec sched_yield(ctx()) :: integer()
  def sched_yield(ctx), do: :wa_wasi_preview1.sched_yield(ctx)

  @doc "See `:wa_wasi_preview1.fd_fdstat_get/4`."
  @spec fd_fdstat_get(accessor(), ctx(), integer(), integer()) :: integer()
  def fd_fdstat_get(accessor, ctx, fd, buf_ptr) do
    :wa_wasi_preview1.fd_fdstat_get(accessor, ctx, fd, buf_ptr)
  end

  @doc "See `:wa_wasi_preview1.fd_read/6`."
  @spec fd_read(accessor(), ctx(), integer(), integer(), integer(), integer()) :: integer()
  def fd_read(accessor, ctx, fd, iovs_ptr, iovs_len, nread_ptr) do
    :wa_wasi_preview1.fd_read(accessor, ctx, fd, iovs_ptr, iovs_len, nread_ptr)
  end
end
