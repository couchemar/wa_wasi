defmodule WaWasi.SchedYieldTest do
  use ExUnit.Case, async: true

  # Feature: preview1-nonfs-completion, Property 4: sched_yield is a pure success.
  # Validates: Requirements 5.2, 5.3.
  #
  # Example-based. sched_yield is a no-op: it always returns ESUCCESS, touches no
  # linear memory, and requires no Config_Context capability.

  @esuccess :wa_wasi_preview1.esuccess()

  test "returns ESUCCESS for an empty context and a fully populated context" do
    empty = :wa_wasi_ctx.new(%{})

    populated =
      :wa_wasi_ctx.new(%{
        stdout: :collect,
        args: [<<"prog">>],
        env: [{<<"K">>, <<"V">>}],
        clock: {:fixed, 1, 2},
        rng: {:fixed, <<0xAA>>},
        stdin: {:fixed, <<"in">>},
        clock_res: {:fixed, 1000, 1}
      })

    assert :wa_wasi_preview1.sched_yield(empty) == @esuccess
    assert :wa_wasi_preview1.sched_yield(populated) == @esuccess
  end
end
