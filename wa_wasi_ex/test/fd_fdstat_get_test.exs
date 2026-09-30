defmodule WaWasi.FdFdstatGetTest do
  use ExUnit.Case, async: true

  alias WaWasi.TestMemory

  # Feature: preview1-nonfs-completion — fd_fdstat_get.
  # Example-based, driven against the binary-backed TestMemory accessor. The
  # 24-byte fdstat struct is decoded field-by-field (including the padding bytes
  # at offset 1 and 4..7) against the authoritative WASI preview1 layout.

  @esuccess :wa_wasi_preview1.esuccess()
  @ebadf :wa_wasi_preview1.ebadf()
  @efault :wa_wasi_preview1.efault()

  # WASI preview1 constants under test.
  @filetype_character_device 2
  @fdflags_none 0
  @rights_fd_read Bitwise.bsl(1, 1)
  @rights_fd_write Bitwise.bsl(1, 6)

  defp acc(size) do
    handle = TestMemory.new(size)
    {{TestMemory, handle}, handle}
  end

  # Decode the 24-byte fdstat struct at `ptr`: {filetype, pad1, flags, pad4_7,
  # rights_base, rights_inheriting}.
  defp read_fdstat(a, ptr) do
    {:ok,
     <<filetype::8, pad1::8, flags::16-little, pad4_7::32-little, rights_base::64-little,
       rights_inh::64-little>>} = :wa_wasi_memory.read(a, ptr, 24)

    %{
      filetype: filetype,
      pad1: pad1,
      flags: flags,
      pad4_7: pad4_7,
      rights_base: rights_base,
      rights_inheriting: rights_inh
    }
  end

  # Property 5: fd_fdstat_get struct fidelity for the standard fds.
  # Validates: Requirements 6.2, 6.3, 6.4, 6.5, 10.2.
  describe "fd_fdstat_get struct fidelity (Property 5)" do
    test "fd 1 (stdout) and fd 2 (stderr): character_device with the fd_write right" do
      ctx = :wa_wasi_ctx.new(%{stdout: :collect, stderr: :collect})

      for fd <- [1, 2] do
        {a, _h} = acc(24)
        assert :wa_wasi_preview1.fd_fdstat_get(a, ctx, fd, 0) == @esuccess

        s = read_fdstat(a, 0)
        assert s.filetype == @filetype_character_device
        assert s.flags == @fdflags_none
        assert s.rights_base == @rights_fd_write
        assert s.rights_inheriting == 0
        # padding bytes are zero
        assert s.pad1 == 0
        assert s.pad4_7 == 0
      end
    end

    test "fd 0 (stdin) with a configured source: character_device with the fd_read right" do
      {a, _h} = acc(24)
      ctx = :wa_wasi_ctx.new(%{stdin: {:fixed, <<"in">>}})

      assert :wa_wasi_preview1.fd_fdstat_get(a, ctx, 0, 0) == @esuccess

      s = read_fdstat(a, 0)
      assert s.filetype == @filetype_character_device
      assert s.flags == @fdflags_none
      assert s.rights_base == @rights_fd_read
      assert s.rights_inheriting == 0
      assert s.pad1 == 0
      assert s.pad4_7 == 0
    end

    test "the struct is written at a nonzero offset without disturbing neighbors" do
      {a, h} = acc(32)
      ctx = :wa_wasi_ctx.new(%{stdout: :collect})
      # write at offset 8; bytes 0..7 must stay zero
      assert :wa_wasi_preview1.fd_fdstat_get(a, ctx, 1, 8) == @esuccess
      assert binary_part(TestMemory.dump(h), 0, 8) == <<0::64>>
      assert read_fdstat(a, 8).filetype == @filetype_character_device
    end
  end

  # Property 6: fd_fdstat_get rejects unreadable/unknown fds.
  # Validates: Requirements 6.6, 6.7, 10.5.
  describe "fd_fdstat_get rejects unreadable/unknown fds (Property 6)" do
    test "fd 0 with no stdin source is EBADF, nothing written" do
      {a, h} = acc(24)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{})
      assert :wa_wasi_preview1.fd_fdstat_get(a, ctx, 0, 0) == @ebadf
      assert TestMemory.dump(h) == before
    end

    test "fds outside {0,1,2} are EBADF, nothing written" do
      {a, h} = acc(24)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{stdout: :collect, stdin: {:fixed, <<"x">>}})

      for fd <- [3, 5, 42] do
        assert :wa_wasi_preview1.fd_fdstat_get(a, ctx, fd, 0) == @ebadf
      end

      assert TestMemory.dump(h) == before
    end
  end

  # Property 9 (fd_fdstat_get slice): EFAULT atomicity.
  # Validates: Requirements 1.4, 6.8, 10.5.
  describe "EFAULT atomicity (Property 9)" do
    test "an OOB buffer pointer returns EFAULT, memory unchanged" do
      {a, h} = acc(24)
      before = TestMemory.dump(h)
      ctx = :wa_wasi_ctx.new(%{stdout: :collect})
      # need 24 bytes; pointer 8 leaves only 16 -> OOB
      assert :wa_wasi_preview1.fd_fdstat_get(a, ctx, 1, 8) == @efault
      assert TestMemory.dump(h) == before
    end
  end
end
