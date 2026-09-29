defmodule WaWasi.FdWriteTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Example-based fd_write tests (no random generation, per Req 12.3), run
  # against the binary-backed TestMemory accessor with a `collect` sink so
  # output is readable via :wa_wasi_preview1.collected/1.

  @esuccess :wa_wasi_preview1.esuccess()
  @ebadf :wa_wasi_preview1.ebadf()
  @efault :wa_wasi_preview1.efault()

  # A context whose stdout (fd 1) and stderr (fd 2) both collect output.
  defp ctx, do: :wa_wasi_ctx.new(%{stdout: :collect, stderr: :collect})

  # u32 little-endian helper for laying out memory by hand.
  defp u32(v), do: <<v::32-little-unsigned>>

  # Build a memory image: a region of iovec records at `iovs_ptr` and the
  # referenced buffers, returning {image_binary}. We place iovecs first, then
  # buffers, in a single flat binary.
  #
  # bufs :: [binary()] — each becomes one iovec pointing at its bytes.
  # Layout: [iovec array (8*N)] [buf0] [buf1] ...  and a 4-byte nwritten slot
  # at the very end.
  defp build_image(bufs) do
    n = length(bufs)
    iov_bytes = n * 8
    # buffers start right after the iovec array
    {iovecs, _off, bufdata} =
      Enum.reduce(bufs, {[], iov_bytes, <<>>}, fn buf, {iovs, off, data} ->
        len = byte_size(buf)
        iov = u32(off) <> u32(len)
        {[iov | iovs], off + len, data <> buf}
      end)

    iov_array = iovecs |> Enum.reverse() |> IO.iodata_to_binary()
    body = iov_array <> bufdata
    nwritten_ptr = byte_size(body)
    image = body <> u32(0)
    # iovs_ptr = 0 (iovec array is at the front)
    %{image: image, iovs_ptr: 0, iovs_len: n, nwritten_ptr: nwritten_ptr}
  end

  defp read_u32(handle, ptr) do
    {:ok, <<v::32-little-unsigned>>} =
      :wa_wasi_memory.read({TestMemory, handle}, ptr, 4)

    v
  end

  # Feature: wasi-preview1, Property 4: fd_write output fidelity.
  # Validates: Requirements 3.2, 3.3, 4.2, 4.3, 4.4, 4.5, 4.7, 10.2, 10.3.
  describe "fd_write output fidelity (Property 4)" do
    test "single iovec to fd 1 (stdout)" do
      %{image: image, iovs_ptr: ip, iovs_len: il, nwritten_ptr: np} =
        build_image([<<"hello">>])

      handle = TestMemory.new(image)
      acc = {TestMemory, handle}
      c = ctx()

      assert :wa_wasi_preview1.fd_write(acc, c, 1, ip, il, np) == @esuccess
      assert :wa_wasi_preview1.collected(1) == <<"hello">>
      assert read_u32(handle, np) == 5
    end

    test "multiple iovecs concatenate in ascending index order to fd 2 (stderr)" do
      %{image: image, iovs_ptr: ip, iovs_len: il, nwritten_ptr: np} =
        build_image([<<"foo">>, <<"-">>, <<"bar!">>])

      handle = TestMemory.new(image)
      acc = {TestMemory, handle}
      c = ctx()

      assert :wa_wasi_preview1.fd_write(acc, c, 2, ip, il, np) == @esuccess
      assert :wa_wasi_preview1.collected(2) == <<"foo-bar!">>
      assert read_u32(handle, np) == 8
    end

    test "IovsLen == 0 writes 0 to Nwritten and emits nothing (Req 4.6)" do
      # a bare memory with just a 4-byte nwritten slot at offset 0
      handle = TestMemory.new(<<0, 0, 0, 0>>)
      acc = {TestMemory, handle}
      c = ctx()

      assert :wa_wasi_preview1.fd_write(acc, c, 1, 0, 0, 0) == @esuccess
      assert read_u32(handle, 0) == 0
      assert :wa_wasi_preview1.collected(1) == <<>>
    end
  end

  # Feature: wasi-preview1, Property 5: fd_write rejects bad file descriptors.
  # Validates: Requirements 4.8, 10.5.
  describe "fd_write rejects bad file descriptors (Property 5)" do
    test "fds outside {1,2} return EBADF and write nothing" do
      %{image: image, iovs_ptr: ip, iovs_len: il, nwritten_ptr: np} =
        build_image([<<"x">>])

      handle = TestMemory.new(image)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      c = ctx()

      for bad_fd <- [0, 3, 42] do
        assert :wa_wasi_preview1.fd_write(acc, c, bad_fd, ip, il, np) == @ebadf
      end

      # nothing written to memory or the sinks
      assert TestMemory.dump(handle) == before
      assert :wa_wasi_preview1.collected(1) == <<>>
      assert :wa_wasi_preview1.collected(2) == <<>>
    end
  end

  # Feature: wasi-preview1, Property 3 (fd_write slice): EFAULT atomicity.
  # Validates: Requirements 2.5, 4.9, 10.4.
  describe "fd_write EFAULT atomicity (Property 3)" do
    test "an out-of-bounds iovec buffer returns EFAULT, no sink output, memory unchanged" do
      # iovec 0 points past the end of memory (ptr 1000, well beyond size).
      # Layout: one iovec at offset 0 -> {ptr: 1000, len: 4}; then a 4-byte
      # in-bounds nwritten slot at offset 8. Total 32 bytes so ONLY the iovec
      # buffer read is out of bounds (the nwritten write at 8 would be valid),
      # isolating the EFAULT to the iovec-buffer path.
      image = <<u32(1000)::binary, u32(4)::binary, 0::size(24)-unit(8)>>
      handle = TestMemory.new(image)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      c = ctx()

      # nwritten_ptr = 8 (in-bounds), iovs at 0, 1 iovec
      assert :wa_wasi_preview1.fd_write(acc, c, 1, 0, 1, 8) == @efault
      assert TestMemory.dump(handle) == before
      assert :wa_wasi_preview1.collected(1) == <<>>
    end

    test "an out-of-bounds Nwritten pointer returns EFAULT with no sink output" do
      %{image: image, iovs_ptr: ip, iovs_len: il} = build_image([<<"data">>])
      handle = TestMemory.new(image)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      c = ctx()

      # point Nwritten far past the end
      assert :wa_wasi_preview1.fd_write(acc, c, 1, ip, il, 100_000) == @efault
      assert TestMemory.dump(handle) == before
      assert :wa_wasi_preview1.collected(1) == <<>>
    end
  end
end
