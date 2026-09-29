defmodule WaWasi.ProcExitTest do
  use ExUnit.Case, async: true

  # Feature: wasi-preview1, Property 11: proc_exit is a catchable exit.
  # Validates: Requirements 9.2, 9.3, 9.4.
  #
  # Example-based (no random generation, per Req 12.3). proc_exit raises the
  # catchable Erlang error {wasi_exit, Code}; it never returns a value and never
  # terminates the BEAM — the calling process catches it and continues.

  # An empty context suffices; proc_exit ignores it.
  defp ctx, do: :wa_wasi_ctx.new(%{})

  test "raises a catchable {wasi_exit, Code} carrying the exit code" do
    for code <- [0, 1, 42] do
      assert {:wasi_exit, ^code} = catch_error(:wa_wasi_preview1.proc_exit(ctx(), code))
    end
  end

  test "the exit code is interpreted unsigned (masked to 32 bits)" do
    # -1 -> 0xFFFFFFFF (4294967295)
    assert {:wasi_exit, 0xFFFFFFFF} = catch_error(:wa_wasi_preview1.proc_exit(ctx(), -1))
    # a value above the u32 range wraps to its low 32 bits
    assert {:wasi_exit, 0} = catch_error(:wa_wasi_preview1.proc_exit(ctx(), 0x1_0000_0000))
  end

  test "the calling process survives (not a BEAM-terminating halt)" do
    # Run in a child we monitor: if proc_exit halted or killed the VM/process
    # uncatchably, the try/catch below could not report :survived.
    parent = self()

    child =
      spawn(fn ->
        result =
          try do
            :wa_wasi_preview1.proc_exit(ctx(), 7)
          catch
            :error, {:wasi_exit, c} -> {:caught, c}
          end

        send(parent, {:child_result, self(), result})
      end)

    assert_receive {:child_result, ^child, {:caught, 7}}, 1_000
    # and the current test process is obviously still alive
    assert Process.alive?(self())
  end
end
