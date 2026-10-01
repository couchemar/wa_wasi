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
  alias WaWasi.TestMemory, as: TestMemory

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

  # -- Task 10.1: clock_res_get + sched_yield end-to-end ----------------------

  test "clock_res_get writes the configured fixed clock resolutions" do
    # fixed realtime resolution = 1000 ns, monotonic = 1 ns
    ctx = :wa_wasi_ctx.new(%{clock_res: {:fixed, 1000, 1}})
    mod = compile!("07_clock_res", ctx)

    assert call(mod, "realtime", []) == @esuccess
    assert call(mod, "read64", [0]) == 1000

    assert call(mod, "monotonic", []) == @esuccess
    assert call(mod, "read64", [8]) == 1
  end

  test "sched_yield returns ESUCCESS" do
    ctx = :wa_wasi_ctx.new(%{})
    mod = compile!("08_sched_yield", ctx)

    assert call(mod, "run", []) == @esuccess
  end

  # -- Task 10.2: fd_fdstat_get + fd_read end-to-end --------------------------

  test "fd_fdstat_get writes the fdstat struct for fd 1 and fd 0" do
    # stdin configured so fd 0 resolves to a readable character device
    ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"x">>}})
    mod = compile!("09_fd_fdstat_get", ctx)

    # fd 1 (stdout) struct at offset 0
    assert call(mod, "stdout", []) == @esuccess
    # fs_filetype @0 = character_device (2)
    assert call(mod, "read8", [0]) == 2
    # padding byte @1 = 0
    assert call(mod, "read8", [1]) == 0
    # fs_flags @2 = 0
    assert call(mod, "read16", [2]) == 0
    # fs_rights_base @8 = fd_write right (bit 6 = 64)
    assert call(mod, "read64", [8]) == 64
    # fs_rights_inheriting @16 = 0
    assert call(mod, "read64", [16]) == 0

    # fd 0 (stdin) struct at offset 32
    assert call(mod, "stdin", []) == @esuccess
    assert call(mod, "read8", [32]) == 2
    assert call(mod, "read16", [34]) == 0
    # fs_rights_base = fd_read right (bit 1 = 2)
    assert call(mod, "read64", [40]) == 2
    assert call(mod, "read64", [48]) == 0
  end

  test "fd_read fills the iovec buffers from the configured stdin and writes nread" do
    # 6 bytes into two 4-byte buffers: buf0 gets "ABCD", buf1 gets "EF"
    ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"ABCDEF">>}})
    mod = compile!("10_fd_read", ctx)

    assert call(mod, "run", []) == @esuccess
    # total bytes read
    assert call(mod, "nread", []) == 6
    # buffer 0 at offset 32: "ABCD"
    buf0 = for i <- 0..3, do: call(mod, "read8", [32 + i])
    assert buf0 == [?A, ?B, ?C, ?D]
    # buffer 1 at offset 40: "EF" then the two untouched bytes stay 0
    buf1 = for i <- 0..3, do: call(mod, "read8", [40 + i])
    assert buf1 == [?E, ?F, 0, 0]
  end

  # -- Task 8.2 (Property 10): import-map arity and coverage ------------------
  # Verify the four new import-map entries are present with the exact WASM arity
  # (2/0/2/4) AND that invoking each closure dispatches to the corresponding
  # wa_wasi_preview1 host function with the captured Accessor/Ctx — observed via
  # a fixed-source side effect / return value. Req 8.1-8.3.
  describe "wa_wasi:imports/2 import-map coverage (Property 10)" do
    # A binary-backed Memory_Accessor for the pure layer (no wa_embedder).
    defp probe_mem(size) do
      handle = WaWasi.TestMemory.new(size)
      {{WaWasi.TestMemory, handle}, handle}
    end

    defp preview1_ns(acc, ctx) do
      imports = WaWasi.imports(acc, ctx)
      Map.fetch!(imports, <<"wasi_snapshot_preview1">>)
    end

    test "clock_res_get: arity 2 and dispatches, writing the configured resolution" do
      ctx = WaWasi.context(%{clock_res: {:fixed, 1000, 25}})
      {acc, handle} = probe_mem(8)
      ns = preview1_ns(acc, ctx)
      fun = Map.fetch!(ns, <<"clock_res_get">>)

      assert is_function(fun, 2)
      # id 0 (realtime) -> write the configured 1000 ns resolution at offset 0
      assert fun.(0, 0) == @esuccess
      assert WaWasi.TestMemory.dump(handle) == <<1000::64-little>>
    end

    test "sched_yield: arity 0 and dispatches to a pure success" do
      ctx = WaWasi.context(%{})
      {acc, _handle} = probe_mem(8)
      ns = preview1_ns(acc, ctx)
      fun = Map.fetch!(ns, <<"sched_yield">>)

      assert is_function(fun, 0)
      assert fun.() == @esuccess
    end

    test "fd_fdstat_get: arity 2 and dispatches, writing the fd 1 fdstat struct" do
      ctx = WaWasi.context(%{})
      {acc, handle} = probe_mem(24)
      ns = preview1_ns(acc, ctx)
      fun = Map.fetch!(ns, <<"fd_fdstat_get">>)

      assert is_function(fun, 2)
      # fd 1 (stdout) -> a 24-byte fdstat struct written at offset 0
      assert fun.(1, 0) == @esuccess
      struct = WaWasi.TestMemory.dump(handle)
      assert byte_size(struct) == 24
      # filetype byte 0 = character_device (2)
      assert binary_part(struct, 0, 1) == <<2>>
    end

    test "fd_read: arity 4 and dispatches, filling from the configured stdin" do
      ctx = WaWasi.context(%{stdin: {:fixed, <<"hi">>}})
      # layout: iovec array at 0 ({ptr=16, len=2}), nread slot at 8, buffer at 16
      {acc, handle} = probe_mem(32)
      {WaWasi.TestMemory, h} = acc
      :ok = WaWasi.TestMemory.write_bytes(h, 0, <<16::32-little, 2::32-little>>)
      ns = preview1_ns(acc, ctx)
      fun = Map.fetch!(ns, <<"fd_read">>)

      assert is_function(fun, 4)
      # fd 0, iovs at 0, 1 iovec, nread at 8
      assert fun.(0, 0, 1, 8) == @esuccess
      mem = WaWasi.TestMemory.dump(handle)
      # the two stdin bytes landed in the buffer at offset 16
      assert binary_part(mem, 16, 2) == <<"hi">>
      # nread slot holds 2
      assert binary_part(mem, 8, 4) == <<2::32-little>>
    end
  end

  # -- Task 9.2: wrapper passthrough (new functions + context keys) -------
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

    test "context/1 accepts :stdin and :clock_res keys (Req 9.3)" do
      # Test :stdin with both fixed and fun shapes
      stdin_fixed = WaWasi.context(%{stdin: {:fixed, <<"test">>}})
      assert :wa_wasi_ctx.stdin(stdin_fixed) == {:fixed, <<"test">>}

      stdin_fun = WaWasi.context(%{stdin: {:fun, fn _max -> {<<1::8>>, :fixed} end}})
      assert {:fun, _} = :wa_wasi_ctx.stdin(stdin_fun)

      # Test :clock_res with both fixed and fun shapes
      clock_res_fixed = WaWasi.context(%{clock_res: {:fixed, 1000, 1}})
      assert :wa_wasi_ctx.clock_res(clock_res_fixed) == {:fixed, 1000, 1}

      clock_res_fun = WaWasi.context(%{clock_res: {:fun, fn _ -> 25 end}})
      assert {:fun, _} = :wa_wasi_ctx.clock_res(clock_res_fun)

      # Verify round-trip through accessors
      opts = %{
        stdin: {:fixed, <<"input">>},
        clock_res: {:fixed, 1000, 25}
      }

      ctx = WaWasi.context(opts)
      assert :wa_wasi_ctx.stdin(ctx) == {:fixed, <<"input">>}
      assert :wa_wasi_ctx.clock_res(ctx) == {:fixed, 1000, 25}
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

    # Task 9.2: new passthroughs delegate to their :wa_wasi_preview1 counterparts
    test "clock_res_get/4 delegates to :wa_wasi_preview1.clock_res_get/4" do
      ctx = WaWasi.context(%{clock_res: {:fixed, 1000, 25}})
      handle = TestMemory.new(8)
      acc = {TestMemory, handle}
      ret = WaWasi.clock_res_get(acc, ctx, 0, 0)
      assert ret == :wa_wasi_preview1.esuccess()
      # The host wrote the resolution (1000 ns) at offset 0
      assert TestMemory.dump(handle) == <<1000::64-little>>
    end

    test "sched_yield/1 delegates to :wa_wasi_preview1.sched_yield/1" do
      ctx = WaWasi.context(%{})
      ret = WaWasi.sched_yield(ctx)
      assert ret == :wa_wasi_preview1.esuccess()
    end

    test "fd_fdstat_get/4 delegates to :wa_wasi_preview1.fd_fdstat_get/4" do
      ctx = WaWasi.context(%{})
      handle = TestMemory.new(24)
      acc = {TestMemory, handle}
      ret = WaWasi.fd_fdstat_get(acc, ctx, 1, 0)
      assert ret == :wa_wasi_preview1.esuccess()
      # The host wrote the fd 1 fdstat struct at offset 0
      struct = TestMemory.dump(handle)
      assert byte_size(struct) == 24
      # character_device
      assert binary_part(struct, 0, 1) == <<2>>
    end

    test "fd_read/6 delegates to :wa_wasi_preview1.fd_read/6" do
      ctx = WaWasi.context(%{stdin: {:fixed, <<"hello">>}})
      # Setup: iovec array at 0 ({ptr=16, len=5}), nread slot at 8, buffer at 16
      handle = TestMemory.new(32)
      acc = {TestMemory, handle}
      :ok = TestMemory.write_bytes(handle, 0, <<16::32-little, 5::32-little>>)
      ret = WaWasi.fd_read(acc, ctx, 0, 0, 1, 8)
      assert ret == :wa_wasi_preview1.esuccess()
      # The host filled the buffer with the first 5 bytes from stdin
      mem = TestMemory.dump(handle)
      assert binary_part(mem, 16, 5) == <<"hello">>
    end
  end
end
