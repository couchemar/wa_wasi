defmodule WaWasi.ClockRandomTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Example-based clock/random tests (no random generation, per Req 12.3),
  # driven against the binary-backed TestMemory accessor with {fixed, ...}
  # clock and rng sources for deterministic, known-output assertions.

  @esuccess :wa_wasi_preview1.esuccess()
  @einval :wa_wasi_preview1.einval()
  @efault :wa_wasi_preview1.efault()

  defp acc(size) do
    handle = TestMemory.new(size)
    {{TestMemory, handle}, handle}
  end

  defp read_i64(a, ptr) do
    {:ok, <<v::64-little-signed>>} = :wa_wasi_memory.read(a, ptr, 8)
    v
  end

  # Feature: wasi-preview1, Property 8: clock_time_get timestamp round-trip.
  # Validates: Requirements 7.2, 7.3, 10.2, 10.3.
  describe "clock_time_get round-trip (Property 8)" do
    test "realtime (id 0) and monotonic (id 1) write the configured fixed value" do
      {a, _h} = acc(16)
      # fixed realtime = 1_700_000_000_000_000_000 ns, monotonic = 42
      ctx = :wa_wasi_ctx.new(%{clock: {:fixed, 1_700_000_000_000_000_000, 42}})

      assert :wa_wasi_preview1.clock_time_get(a, ctx, 0, 0, 0) == @esuccess
      assert read_i64(a, 0) == 1_700_000_000_000_000_000

      assert :wa_wasi_preview1.clock_time_get(a, ctx, 1, 0, 8) == @esuccess
      assert read_i64(a, 8) == 42
    end

    test "precision argument is ignored (value comes only from the source)" do
      {a, _h} = acc(8)
      ctx = :wa_wasi_ctx.new(%{clock: {:fixed, 999, 7}})
      # a nonzero precision must not change the written value
      assert :wa_wasi_preview1.clock_time_get(a, ctx, 0, 123_456, 0) == @esuccess
      assert read_i64(a, 0) == 999
    end
  end

  # Feature: wasi-preview1, Property 9: clock_time_get rejects unknown clock ids.
  # Validates: Requirements 7.4, 10.5.
  describe "clock_time_get rejects unknown clock ids (Property 9)" do
    test "ids other than 0/1 return EINVAL and write nothing" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{clock: {:fixed, 1, 2}})

      for bad_id <- [2, 3, -1, 999] do
        assert :wa_wasi_preview1.clock_time_get(a, ctx, bad_id, 0, 0) == @einval
      end

      assert TestMemory.dump(h) == before
    end
  end

  # Feature: wasi-preview1, Property 10: random_get length and source fidelity.
  # Validates: Requirements 8.2, 8.3, 10.2.
  describe "random_get length and source fidelity (Property 10)" do
    test "writes exactly the source bytes for len > 0" do
      {a, _h} = acc(16)
      # fixed seed cycles/truncates to the requested length
      ctx = :wa_wasi_ctx.new(%{rng: {:fixed, <<0xAA, 0xBB, 0xCC>>}})
      assert :wa_wasi_preview1.random_get(a, ctx, 0, 7) == @esuccess
      # 7 bytes = seed cycled: AA BB CC AA BB CC AA
      assert {:ok, <<0xAA, 0xBB, 0xCC, 0xAA, 0xBB, 0xCC, 0xAA>>} =
               :wa_wasi_memory.read(a, 0, 7)
    end

    test "len 0 is a no-op success and writes nothing" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{rng: {:fixed, <<1, 2, 3>>}})
      assert :wa_wasi_preview1.random_get(a, ctx, 0, 0) == @esuccess
      assert TestMemory.dump(h) == before
    end

    test "a {fun, F} source supplies the exact bytes" do
      {a, _h} = acc(8)
      ctx = :wa_wasi_ctx.new(%{rng: {:fun, fn n -> :binary.copy(<<0x5A>>, n) end}})
      assert :wa_wasi_preview1.random_get(a, ctx, 2, 4) == @esuccess
      assert {:ok, <<0x5A, 0x5A, 0x5A, 0x5A>>} = :wa_wasi_memory.read(a, 2, 4)
    end
  end

  # Feature: wasi-preview1, Property 3 (clock/random slice): EFAULT atomicity.
  # Validates: Requirements 7.5, 8.4, 10.4.
  describe "EFAULT atomicity (Property 3)" do
    test "clock_time_get: an OOB time pointer returns EFAULT, memory unchanged" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{clock: {:fixed, 5, 6}})
      # need 8 bytes; pointer 4 leaves only 4 -> OOB
      assert :wa_wasi_preview1.clock_time_get(a, ctx, 0, 0, 4) == @efault
      assert TestMemory.dump(h) == before
    end

    test "random_get: an OOB buffer returns EFAULT, memory unchanged" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{rng: {:fixed, <<0xFF>>}})
      # write 4 bytes at offset 6 -> OOB
      assert :wa_wasi_preview1.random_get(a, ctx, 6, 4) == @efault
      assert TestMemory.dump(h) == before
    end
  end
end
