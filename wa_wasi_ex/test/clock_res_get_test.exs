defmodule WaWasi.ClockResGetTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Feature: preview1-nonfs-completion — clock_res_get.
  # Example-based (no random generation): driven against the binary-backed
  # TestMemory accessor with {fixed, ...} / {fun, ...} clock-resolution sources
  # for deterministic, known-output assertions.

  @esuccess :wa_wasi_preview1.esuccess()
  @einval :wa_wasi_preview1.einval()
  @efault :wa_wasi_preview1.efault()

  defp acc(size) do
    handle = TestMemory.new(size)
    {{TestMemory, handle}, handle}
  end

  defp read_u64(a, ptr) do
    {:ok, <<v::64-little-unsigned>>} = :wa_wasi_memory.read(a, ptr, 8)
    v
  end

  # Property 2: clock_res_get resolution round-trip.
  # Validates: Requirements 4.2, 4.3, 10.2.
  describe "clock_res_get resolution round-trip (Property 2)" do
    test "realtime (id 0) and monotonic (id 1) write the configured fixed resolution" do
      {a, _h} = acc(16)
      # fixed realtime resolution = 1000 ns, monotonic = 1 ns
      ctx = :wa_wasi_ctx.new(%{clock_res: {:fixed, 1000, 1}})

      assert :wa_wasi_preview1.clock_res_get(a, ctx, 0, 0) == @esuccess
      assert read_u64(a, 0) == 1000

      assert :wa_wasi_preview1.clock_res_get(a, ctx, 1, 8) == @esuccess
      assert read_u64(a, 8) == 1
    end

    test "a {fun, F} source supplies the resolution per clock kind" do
      {a, _h} = acc(8)
      ctx = :wa_wasi_ctx.new(%{clock_res: {:fun, fn :realtime -> 42 end}})
      assert :wa_wasi_preview1.clock_res_get(a, ctx, 0, 0) == @esuccess
      assert read_u64(a, 0) == 42
    end
  end

  # Property 3: clock_res_get rejects unknown clock ids.
  # Validates: Requirements 4.4, 10.5.
  describe "clock_res_get rejects unknown clock ids (Property 3)" do
    test "ids other than 0/1 (incl. 2 and 3) return EINVAL and write nothing" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{clock_res: {:fixed, 1, 2}})

      for bad_id <- [2, 3, -1, 7] do
        assert :wa_wasi_preview1.clock_res_get(a, ctx, bad_id, 0) == @einval
      end

      assert TestMemory.dump(h) == before
    end
  end

  describe "missing capability (Req 4.6)" do
    test "an absent Clock_Resolution_Source raises {missing_capability, clock_res}" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{})

      assert {:missing_capability, :clock_res} =
               catch_error(:wa_wasi_preview1.clock_res_get(a, ctx, 0, 0))

      # no host fallback, nothing written
      assert TestMemory.dump(h) == before
    end
  end

  # Property 9 (clock_res_get slice): EFAULT atomicity.
  # Validates: Requirements 1.4, 4.5, 10.5.
  describe "EFAULT atomicity (Property 9)" do
    test "an OOB resolution pointer returns EFAULT, memory unchanged" do
      {a, h} = acc(8)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{clock_res: {:fixed, 5, 6}})
      # need 8 bytes; pointer 4 leaves only 4 -> OOB
      assert :wa_wasi_preview1.clock_res_get(a, ctx, 0, 4) == @efault
      assert TestMemory.dump(h) == before
    end
  end
end
