defmodule WaWasi.MemoryTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Feature: wasi-preview1, Property 2: Accessor read returns the requested length.
  # Validates: Requirements 2.4.
  #
  # Example-based (no random generation, per Req 12.3): a binary-backed
  # :wa_wasi_memory accessor over known contents, with hand-chosen in-bounds
  # (offset, len) reads including len 0 and len > 0.

  @contents <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15>>

  defp accessor do
    {TestMemory, TestMemory.new(@contents)}
  end

  describe "read/3 returns exactly the requested length (Property 2)" do
    test "in-bounds reads return a binary of exactly Len bytes" do
      acc = accessor()

      for {offset, len} <- [{0, 0}, {0, 1}, {4, 4}, {0, 16}, {15, 1}, {8, 0}] do
        assert {:ok, bytes} = :wa_wasi_memory.read(acc, offset, len)
        assert byte_size(bytes) == len
      end
    end

    test "returned bytes are the requested slice, in order" do
      acc = accessor()
      assert {:ok, <<4, 5, 6, 7>>} = :wa_wasi_memory.read(acc, 4, 4)
      assert {:ok, <<>>} = :wa_wasi_memory.read(acc, 0, 0)
      assert {:ok, @contents} = :wa_wasi_memory.read(acc, 0, 16)
    end
  end

  describe "read/3 bounds guarding (Req 2.5)" do
    test "a range past the end is efault" do
      acc = accessor()
      # 16 bytes total; reading 1 byte at offset 16 is out of bounds
      assert {:error, :efault} = :wa_wasi_memory.read(acc, 16, 1)
      # partially past the end
      assert {:error, :efault} = :wa_wasi_memory.read(acc, 14, 4)
    end

    test "negative offset or length is efault" do
      acc = accessor()
      assert {:error, :efault} = :wa_wasi_memory.read(acc, -1, 4)
      assert {:error, :efault} = :wa_wasi_memory.read(acc, 0, -1)
    end
  end

  describe "write/3 persistence and bounds (Req 2.3, 2.5)" do
    test "an in-bounds write persists and a read sees it" do
      {_mod, handle} = acc = accessor()
      assert :ok = :wa_wasi_memory.write(acc, 4, <<0xAA, 0xBB>>)
      assert {:ok, <<0xAA, 0xBB>>} = :wa_wasi_memory.read(acc, 4, 2)
      # untouched bytes remain
      assert {:ok, <<0, 1, 2, 3>>} = :wa_wasi_memory.read(acc, 0, 4)
      assert byte_size(TestMemory.dump(handle)) == 16
    end

    test "an out-of-bounds write is efault and leaves memory unmodified" do
      {_mod, handle} = acc = accessor()
      before = TestMemory.dump(handle)
      assert {:error, :efault} = :wa_wasi_memory.write(acc, 15, <<1, 2, 3, 4>>)
      assert TestMemory.dump(handle) == before
    end
  end
end
