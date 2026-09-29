defmodule WaWasi.ArgsEnvironTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Example-based args/environ tests (no random generation, per Req 12.3),
  # driven against the binary-backed TestMemory accessor.

  @esuccess :wa_wasi_preview1.esuccess()
  @efault :wa_wasi_preview1.efault()

  defp acc(mem_or_size) do
    handle = TestMemory.new(mem_or_size)
    {{TestMemory, handle}, handle}
  end

  defp read_u32(a, ptr) do
    {:ok, <<v::32-little-unsigned>>} = :wa_wasi_memory.read(a, ptr, 4)
    v
  end

  # Read a NUL-terminated string starting at ptr from the accessor.
  defp read_cstr(a, ptr), do: read_cstr(a, ptr, <<>>)

  defp read_cstr(a, ptr, so_far) do
    {:ok, <<b>>} = :wa_wasi_memory.read(a, ptr, 1)

    case b do
      0 -> so_far
      _ -> read_cstr(a, ptr + 1, <<so_far::binary, b>>)
    end
  end

  # Feature: wasi-preview1, Property 6: sizes accounting for args and environ.
  # Validates: Requirements 5.2, 5.5, 6.2, 6.5.
  describe "sizes accounting (Property 6)" do
    test "args_sizes_get: count and total NUL-terminated buffer size" do
      {a, _h} = acc(64)
      ctx = :wa_wasi_ctx.new(%{args: [<<"prog">>, <<"--flag">>, <<"x">>]})
      # count_ptr = 0, bufsize_ptr = 4
      assert :wa_wasi_preview1.args_sizes_get(a, ctx, 0, 4) == @esuccess
      assert read_u32(a, 0) == 3
      # ("prog"+1) + ("--flag"+1) + ("x"+1) = 5 + 7 + 2 = 14
      assert read_u32(a, 4) == 14
    end

    test "environ_sizes_get: KEY=VALUE entries" do
      {a, _h} = acc(64)
      ctx = :wa_wasi_ctx.new(%{env: [{<<"HOME">>, <<"/root">>}, {<<"X">>, <<"1">>}]})
      assert :wa_wasi_preview1.environ_sizes_get(a, ctx, 0, 4) == @esuccess
      assert read_u32(a, 0) == 2
      # "HOME=/root"(10)+1 + "X=1"(3)+1 = 11 + 4 = 15
      assert read_u32(a, 4) == 15
    end

    test "empty args/env report 0 count and 0 buffer size" do
      {a, _h} = acc(64)
      ctx = :wa_wasi_ctx.new(%{})
      assert :wa_wasi_preview1.args_sizes_get(a, ctx, 0, 4) == @esuccess
      assert read_u32(a, 0) == 0
      assert read_u32(a, 4) == 0

      assert :wa_wasi_preview1.environ_sizes_get(a, ctx, 8, 12) == @esuccess
      assert read_u32(a, 8) == 0
      assert read_u32(a, 12) == 0
    end
  end

  # Feature: wasi-preview1, Property 7: get pointer-array round-trip for args and environ.
  # Validates: Requirements 5.4, 6.4, 10.2, 10.3.
  describe "get pointer-array round-trip (Property 7)" do
    test "args_get: follow each pointer to reconstruct the args in order" do
      {a, _h} = acc(128)
      args = [<<"prog">>, <<"--flag">>, <<"x">>]
      ctx = :wa_wasi_ctx.new(%{args: args})
      # pointer array at 0 (3 * 4 = 12 bytes), string buffer at 32
      buf_ptr = 32
      assert :wa_wasi_preview1.args_get(a, ctx, 0, buf_ptr) == @esuccess

      ptrs = for i <- 0..2, do: read_u32(a, i * 4)
      reconstructed = Enum.map(ptrs, &read_cstr(a, &1))
      assert reconstructed == args
      # first pointer points at the start of the buffer
      assert hd(ptrs) == buf_ptr
    end

    test "environ_get: follow each pointer to reconstruct KEY=VALUE entries in order" do
      {a, _h} = acc(128)
      ctx = :wa_wasi_ctx.new(%{env: [{<<"HOME">>, <<"/root">>}, {<<"X">>, <<"1">>}]})
      buf_ptr = 32
      assert :wa_wasi_preview1.environ_get(a, ctx, 0, buf_ptr) == @esuccess

      ptrs = for i <- 0..1, do: read_u32(a, i * 4)
      reconstructed = Enum.map(ptrs, &read_cstr(a, &1))
      assert reconstructed == [<<"HOME=/root">>, <<"X=1">>]
    end

    test "empty list writes nothing and succeeds" do
      {a, h} = acc(16)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{})
      assert :wa_wasi_preview1.args_get(a, ctx, 0, 8) == @esuccess
      assert :wa_wasi_preview1.environ_get(a, ctx, 0, 8) == @esuccess
      assert TestMemory.dump(h) == before
    end
  end

  # Feature: wasi-preview1, Property 3 (args/environ slice): EFAULT atomicity.
  # Validates: Requirements 5.6, 6.6, 10.4.
  describe "EFAULT atomicity (Property 3)" do
    test "sizes_get: an OOB count/size pointer returns EFAULT, memory unchanged" do
      {a, h} = acc(16)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{args: [<<"a">>]})
      # bufsize_ptr past the end (13 + 4 > 16)
      assert :wa_wasi_preview1.args_sizes_get(a, ctx, 0, 13) == @efault
      assert TestMemory.dump(h) == before
    end

    test "get: an OOB pointer-array or buffer region returns EFAULT, memory unchanged" do
      {a, h} = acc(16)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{args: [<<"hello">>]})
      # buffer pointer past the end
      assert :wa_wasi_preview1.args_get(a, ctx, 0, 100) == @efault
      assert TestMemory.dump(h) == before
      # pointer array past the end
      assert :wa_wasi_preview1.args_get(a, ctx, 100, 0) == @efault
      assert TestMemory.dump(h) == before
    end
  end
end
