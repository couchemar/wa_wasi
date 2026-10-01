defmodule WaWasi.FdReadTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Feature: preview1-nonfs-completion — fd_read.
  # Example-based, driven against the binary-backed TestMemory accessor with
  # {fixed, Bytes} / {fun, F} stdin sources for deterministic known outputs.
  # fd_read reads from stdin (fd 0) into iovec buffers in ascending order.

  @esuccess :wa_wasi_preview1.esuccess()
  @ebadf :wa_wasi_preview1.ebadf()
  @efault :wa_wasi_preview1.efault()

  defp u32(v), do: <<v::32-little-unsigned>>

  # Build a memory image with an iovec array at offset 0 pointing at zeroed
  # destination buffers of the given lengths, plus a 4-byte nread slot at the
  # end. Returns the layout offsets so a test can read back what fd_read wrote.
  defp build_image(buf_lens) do
    n = length(buf_lens)
    iov_bytes = n * 8

    {iovecs, buf_offsets, total_buf} =
      Enum.reduce(buf_lens, {[], [], 0}, fn len, {iovs, offs, off} ->
        ptr = iov_bytes + off
        {[u32(ptr) <> u32(len) | iovs], [ptr | offs], off + len}
      end)

    iov_array = iovecs |> Enum.reverse() |> IO.iodata_to_binary()
    body = iov_array <> <<0::size(total_buf)-unit(8)>>
    nread_ptr = byte_size(body)
    image = body <> u32(0)

    %{
      image: image,
      iovs_ptr: 0,
      iovs_len: n,
      nread_ptr: nread_ptr,
      buf_offsets: buf_offsets |> Enum.reverse()
    }
  end

  defp read_u32(handle, ptr) do
    {:ok, <<v::32-little-unsigned>>} = :wa_wasi_memory.read({TestMemory, handle}, ptr, 4)
    v
  end

  defp read_bytes(handle, ptr, len) do
    {:ok, bytes} = :wa_wasi_memory.read({TestMemory, handle}, ptr, len)
    bytes
  end

  # Property 7: fd_read input fidelity and nread accounting.
  # Validates: Requirements 7.2, 7.3, 7.4, 7.5, 7.6, 10.2.
  describe "fd_read input fidelity and nread accounting (Property 7)" do
    test "single iovec: fills the buffer with the fixed source bytes (bytes == capacity)" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np, buf_offsets: [b0]} =
        build_image([5])

      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"hello">>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, np) == @esuccess
      assert read_u32(handle, np) == 5
      assert read_bytes(handle, b0, 5) == <<"hello">>
    end

    test "multi iovec: fills buffers in ascending order until the source is drained" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np, buf_offsets: [b0, b1, b2]} =
        build_image([3, 3, 3])

      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      # 7 bytes into 3+3+3: fills buf0 (3), buf1 (3), buf2 gets 1
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"ABCDEFG">>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, np) == @esuccess
      assert read_u32(handle, np) == 7
      assert read_bytes(handle, b0, 3) == <<"ABC">>
      assert read_bytes(handle, b1, 3) == <<"DEF">>
      # buf2 got 1 byte then the source drained; the rest stays zero
      assert read_bytes(handle, b2, 3) == <<"G", 0, 0>>
    end

    test "source longer than total capacity fills every buffer and stops" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np, buf_offsets: [b0, b1]} =
        build_image([2, 2])

      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"ABCDEFGH">>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, np) == @esuccess
      # only 4 bytes fit (2+2); the rest of the source is dropped
      assert read_u32(handle, np) == 4
      assert read_bytes(handle, b0, 2) == <<"AB">>
      assert read_bytes(handle, b1, 2) == <<"CD">>
    end

    test "a {fun, F} multi-chunk source threads its state across buffers" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np, buf_offsets: [b0, b1]} =
        build_image([4, 4])

      handle = TestMemory.new(img)
      acc = {TestMemory, handle}

      # A stateful source that yields "wxyz" then "12" then EOF, one chunk per
      # pull, each chunk fitting the requested max.
      src = fn max ->
        case max do
          _ ->
            {binary_part(<<"wxyz">>, 0, min(4, max)),
             {:fun, fn _m -> {<<"12">>, {:fixed, <<>>}} end}}
        end
      end

      ctx = :wa_wasi_ctx.new(%{stdin: {:fun, src}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, np) == @esuccess
      # buf0 gets "wxyz" (4, full), buf1 gets "12" (2, short -> stop). total 6
      assert read_u32(handle, np) == 6
      assert read_bytes(handle, b0, 4) == <<"wxyz">>
      assert read_bytes(handle, b1, 4) == <<"12", 0, 0>>
    end

    test "iovs_len == 0 writes nread 0 and consumes no stdin" do
      handle = TestMemory.new(<<0, 0, 0, 0>>)
      acc = {TestMemory, handle}
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"unused">>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, 0, 0, 0) == @esuccess
      assert read_u32(handle, 0) == 0
    end

    test "an EOF source writes nread 0 and leaves buffers zero" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np, buf_offsets: [b0]} =
        build_image([4])

      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<>>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, np) == @esuccess
      assert read_u32(handle, np) == 0
      assert read_bytes(handle, b0, 4) == <<0, 0, 0, 0>>
    end
  end

  # Property 8: fd_read rejects non-stdin and unconfigured stdin.
  # Validates: Requirements 7.7, 7.8, 10.5.
  describe "fd_read rejects non-stdin and unconfigured stdin (Property 8)" do
    test "fds other than 0 return EBADF and do not touch the nread slot" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np} = build_image([4])
      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"data">>}})

      for bad_fd <- [1, 3, 42] do
        assert :wa_wasi_preview1.fd_read(acc, ctx, bad_fd, ip, il, np) == @ebadf
      end

      assert TestMemory.dump(handle) == before
    end

    test "fd 0 with no stdin source is EBADF, nread untouched" do
      %{image: img, iovs_ptr: ip, iovs_len: il, nread_ptr: np} = build_image([4])
      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      ctx = :wa_wasi_ctx.new(%{})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, np) == @ebadf
      assert TestMemory.dump(handle) == before
    end
  end

  # Property 9 (fd_read slice): EFAULT atomicity, no stdin consumed on fault.
  # Validates: Requirements 1.4, 7.9, 10.5.
  describe "EFAULT atomicity (Property 9)" do
    test "an OOB iovec buffer returns EFAULT, memory unchanged, no stdin consumed" do
      # one iovec at offset 0 -> {ptr: 1000 (OOB), len: 4}; nread slot at 8.
      image = <<u32(1000)::binary, u32(4)::binary, 0::size(24)-unit(8)>>
      handle = TestMemory.new(image)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"hello">>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, 0, 1, 8) == @efault
      assert TestMemory.dump(handle) == before
    end

    test "an OOB nread pointer returns EFAULT, memory unchanged" do
      %{image: img, iovs_ptr: ip, iovs_len: il} = build_image([4])
      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"data">>}})

      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, ip, il, 100_000) == @efault
      assert TestMemory.dump(handle) == before
    end

    test "an OOB iovec array returns EFAULT, memory unchanged" do
      %{image: img} = build_image([4])
      handle = TestMemory.new(img)
      acc = {TestMemory, handle}
      before = TestMemory.dump(handle)
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"data">>}})

      # iovs_ptr past the end, claiming 1 iovec
      assert :wa_wasi_preview1.fd_read(acc, ctx, 0, 100_000, 1, 0) == @efault
      assert TestMemory.dump(handle) == before
    end
  end
end
