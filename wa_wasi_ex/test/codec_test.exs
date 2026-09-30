defmodule WaWasi.CodecTest do
  use ExUnit.Case, async: true

  # Feature: wasi-preview1, Property 1: Little-endian codec round-trip.
  # Validates: Requirements 2.6.
  #
  # Example-based (no random generation, per Req 12.3): hand-chosen u32 and
  # signed i64 values covering 0, 1, the maxima, a mid value, and negatives.
  # Exercises the pure :wa_wasi_preview1 codec helpers directly.

  @u32_max 0xFFFFFFFF
  @i64_min -0x8000000000000000
  @i64_max 0x7FFFFFFFFFFFFFFF

  describe "encode_u32/1 + decode_u32/1" do
    test "round-trip for representative u32 values" do
      for u <- [0, 1, 255, 256, 0x01020304, @u32_max] do
        bytes = :wa_wasi_preview1.encode_u32(u)
        assert byte_size(bytes) == 4
        assert :wa_wasi_preview1.decode_u32(bytes) == u
      end
    end

    test "least-significant byte is at the lowest offset (little-endian)" do
      # 0x01020304 -> bytes 0x04, 0x03, 0x02, 0x01
      assert :wa_wasi_preview1.encode_u32(0x01020304) == <<0x04, 0x03, 0x02, 0x01>>
      # 1 -> low byte first
      assert :wa_wasi_preview1.encode_u32(1) == <<1, 0, 0, 0>>
      # max -> all ones
      assert :wa_wasi_preview1.encode_u32(@u32_max) == <<0xFF, 0xFF, 0xFF, 0xFF>>
    end
  end

  # Feature: preview1-nonfs-completion, Property 1: u16 codec little-endian
  # ordering. Validates: Requirements 1.3.
  describe "encode_u16/1 (u16, little-endian)" do
    test "round-trips representative u16 values via a 2-byte LE decode" do
      for u <- [0, 1, 0x00FF, 0xFF00, 0xFFFF] do
        bytes = :wa_wasi_preview1.encode_u16(u)
        assert byte_size(bytes) == 2
        <<decoded::16-little-unsigned>> = bytes
        assert decoded == u
      end
    end

    test "least-significant byte is at the lowest offset (little-endian)" do
      # 1 -> low byte first
      assert :wa_wasi_preview1.encode_u16(1) == <<1, 0>>
      # 0x00FF -> low byte 0xFF then 0x00
      assert :wa_wasi_preview1.encode_u16(0x00FF) == <<0xFF, 0x00>>
      # 0xFF00 -> low byte 0x00 then 0xFF
      assert :wa_wasi_preview1.encode_u16(0xFF00) == <<0x00, 0xFF>>
      # max -> all ones
      assert :wa_wasi_preview1.encode_u16(0xFFFF) == <<0xFF, 0xFF>>
    end
  end

  describe "encode_u64/1 (signed i64, little-endian)" do
    test "round-trips representative signed i64 values via an 8-byte LE decode" do
      for n <- [0, 1, -1, 42, -42, @i64_min, @i64_max] do
        bytes = :wa_wasi_preview1.encode_u64(n)
        assert byte_size(bytes) == 8
        <<decoded::64-little-signed>> = bytes
        assert decoded == n
      end
    end

    test "least-significant byte is at the lowest offset (little-endian)" do
      # 1 -> low byte first, rest zero
      assert :wa_wasi_preview1.encode_u64(1) == <<1, 0, 0, 0, 0, 0, 0, 0>>
      # -1 -> all ones (two's complement)
      assert :wa_wasi_preview1.encode_u64(-1) ==
               <<0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF>>

      # 0x0102030405060708 -> bytes reversed
      assert :wa_wasi_preview1.encode_u64(0x0102030405060708) ==
               <<0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01>>
    end
  end
end
