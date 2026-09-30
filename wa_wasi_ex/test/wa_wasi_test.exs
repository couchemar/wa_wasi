defmodule WaWasiTest do
  use ExUnit.Case

  # End-to-end (Layer-b) integration tests: real WASM modules that import
  # wasi_snapshot_preview1 functions, compiled and run via wa_embedder_ex
  # (a test-only dependency). The module's linear memory is bridged to wa_wasi
  # through WaWasi.EmbedderMemoryAdapter. Known input -> known output, per
  # Req 12.1-12.3, 12.7.
  #
  # NOT async: compiled modules are named atoms loaded into the global code
  # table, and the linear memory lives in the process dictionary.

  alias WaWasi.EmbedderMemoryAdapter, as: Adapter

  @wat_dir Path.expand("../../test_data/wat", __DIR__)
  @esuccess :wa_wasi_preview1.esuccess()

  defp compile!(name, ctx) do
    mod = String.to_atom(name)
    acc = Adapter.accessor(mod)
    imports = WaWasi.imports(acc, ctx)
    assert {:module, ^mod} = WaEmbedder.compile(Path.join(@wat_dir, name <> ".wasm"), imports, [])
    mod
  end

  defp call(mod, fun, args), do: :erlang.apply(mod, String.to_atom(fun), args)

  # Walk a NUL-terminated string in the module's memory via its read8 export.
  defp read_cstr(mod, ptr), do: read_cstr(mod, ptr, [])

  defp read_cstr(mod, ptr, acc) do
    case call(mod, "read8", [ptr]) do
      0 -> acc |> Enum.reverse() |> IO.iodata_to_binary()
      b -> read_cstr(mod, ptr + 1, [b | acc])
    end
  end

  test "fd_write writes the module's output to the configured stdout sink" do
    ctx = :wa_wasi_ctx.new(%{stdout: :collect, stderr: :collect})
    mod = compile!("01_fd_write_stdout", ctx)

    assert call(mod, "run", []) == @esuccess
    # the collect sink accumulates in THIS process (host fns run here)
    assert :wa_wasi_preview1.collected(1) == "Hello, WASI!\n"
    # the host wrote the total byte count back into memory
    assert call(mod, "nwritten", []) == 13
  end

  test "args_sizes_get / args_get expose the configured arguments" do
    args = [<<"prog">>, <<"--flag">>, <<"x">>]
    ctx = :wa_wasi_ctx.new(%{args: args})
    mod = compile!("02_args", ctx)

    assert call(mod, "sizes", []) == @esuccess
    assert call(mod, "read32", [0]) == 3
    # ("prog"+1)+("--flag"+1)+("x"+1) = 5+7+2 = 14
    assert call(mod, "read32", [4]) == 14

    assert call(mod, "get", []) == @esuccess
    # pointer array at 64: three u32 pointers into the buffer
    ptrs = for i <- 0..2, do: call(mod, "read32", [64 + i * 4])
    reconstructed = Enum.map(ptrs, &read_cstr(mod, &1))
    assert reconstructed == args
    # first arg string sits at the buffer base (128)
    assert hd(ptrs) == 128
  end

  test "environ_sizes_get / environ_get expose the configured environment" do
    ctx = :wa_wasi_ctx.new(%{env: [{<<"HOME">>, <<"/root">>}, {<<"X">>, <<"1">>}]})
    mod = compile!("03_environ", ctx)

    assert call(mod, "sizes", []) == @esuccess
    assert call(mod, "read32", [0]) == 2
    # "HOME=/root"(10)+1 + "X=1"(3)+1 = 11 + 4 = 15
    assert call(mod, "read32", [4]) == 15

    assert call(mod, "get", []) == @esuccess
    ptrs = for i <- 0..1, do: call(mod, "read32", [64 + i * 4])
    reconstructed = Enum.map(ptrs, &read_cstr(mod, &1))
    assert reconstructed == [<<"HOME=/root">>, <<"X=1">>]
  end

  test "clock_time_get writes the configured fixed timestamps" do
    # fixed realtime = 1_700_000_000_000_000_000 ns, monotonic = 42
    ctx = :wa_wasi_ctx.new(%{clock: {:fixed, 1_700_000_000_000_000_000, 42}})
    mod = compile!("04_clock", ctx)

    assert call(mod, "realtime", []) == @esuccess
    assert call(mod, "read64", [0]) == 1_700_000_000_000_000_000

    assert call(mod, "monotonic", []) == @esuccess
    assert call(mod, "read64", [8]) == 42
  end

  test "random_get fills the buffer with the configured fixed bytes" do
    # fixed seed cycles/truncates to the requested length
    ctx = :wa_wasi_ctx.new(%{rng: {:fixed, <<0xAA, 0xBB, 0xCC>>}})
    mod = compile!("05_random", ctx)

    assert call(mod, "fill", [7]) == @esuccess
    # 7 bytes = seed cycled: AA BB CC AA BB CC AA
    bytes = for i <- 0..6, do: call(mod, "read8", [i])
    assert bytes == [0xAA, 0xBB, 0xCC, 0xAA, 0xBB, 0xCC, 0xAA]
  end

  test "proc_exit raises a catchable {wasi_exit, Code} while the process survives" do
    ctx = :wa_wasi_ctx.new(%{})
    mod = compile!("06_proc_exit", ctx)

    # The host raises error:{wasi_exit, Code}, which propagates out of the
    # exported WASM function. The calling (test) process catches it and lives on.
    assert {:wasi_exit, 3} = catch_error(call(mod, "exit", [3]))
    # unsigned interpretation: -1 -> 0xFFFFFFFF
    assert {:wasi_exit, 0xFFFFFFFF} = catch_error(call(mod, "exit", [-1]))
    assert Process.alive?(self())
  end

  # -- Task 14.3: wrapper passthrough -------------------------------------
  # WaWasi's public functions delegate to their :wa_wasi* Erlang counterparts,
  # and only plain terms cross the boundary (no Elixir structs). Req 11.3, 11.6.
  describe "WaWasi wrapper passthrough" do
    test "context/1 delegates to :wa_wasi_ctx.new/1 and returns a plain term" do
      opts = %{args: [<<"a">>], env: [{<<"K">>, <<"V">>}]}
      assert WaWasi.context(opts) == :wa_wasi_ctx.new(opts)
      # a plain Erlang record tuple, not an Elixir struct
      refute is_struct(WaWasi.context(opts))
      assert is_tuple(WaWasi.context(opts))
    end

    test "imports/2 delegates to :wa_wasi.imports/2 with the same shape" do
      ctx = WaWasi.context(%{})
      acc = Adapter.accessor(:passthrough_probe)
      imports = WaWasi.imports(acc, ctx)

      assert imports == :wa_wasi.imports(acc, ctx)
      # the wasi_snapshot_preview1 namespace maps names to arity-exact funs
      ns = Map.fetch!(imports, <<"wasi_snapshot_preview1">>)
      assert is_function(Map.fetch!(ns, <<"fd_write">>), 4)
      assert is_function(Map.fetch!(ns, <<"proc_exit">>), 1)
    end
  end
end
