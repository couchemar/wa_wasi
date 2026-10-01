defmodule WaWasi.CtxTest do
  use ExUnit.Case, async: true

  # Feature: wasi-preview1 — Config_Context defaults + missing-capability rejection.
  # Validates: Requirements 3.4, 3.5, 3.6, 3.7, 1.5.
  #
  # Example-based (no random generation, per Req 12.3). Exercises the pure
  # :wa_wasi_ctx module directly: defaults, field accessors, capability
  # resolution, and the "no implicit host resource" rejection paths.

  describe "new/1 defaults (Req 3.8, 3.9, 3.7)" do
    test "an empty context defaults args/env to [] and sinks/clock/rng to undefined" do
      ctx = :wa_wasi_ctx.new(%{})
      assert :wa_wasi_ctx.args(ctx) == []
      assert :wa_wasi_ctx.env(ctx) == []
      assert :wa_wasi_ctx.stdout(ctx) == :undefined
      assert :wa_wasi_ctx.stderr(ctx) == :undefined
      assert :wa_wasi_ctx.clock(ctx) == :undefined
      assert :wa_wasi_ctx.rng(ctx) == :undefined
      # preview1-nonfs-completion: new capabilities default absent (Req 2.5, 3.5)
      assert :wa_wasi_ctx.stdin(ctx) == :undefined
      assert :wa_wasi_ctx.clock_res(ctx) == :undefined
    end

    test "supplied fields round-trip through the accessors" do
      sink = {:fun, fn _ -> :ok end}
      clock = {:fixed, 111, 222}
      rng = {:fixed, <<1, 2, 3>>}
      stdin = {:fixed, <<"input">>}
      clock_res = {:fixed, 1000, 1}

      ctx =
        :wa_wasi_ctx.new(%{
          stdout: sink,
          stderr: :collect,
          args: [<<"a">>, <<"b">>],
          env: [{<<"K">>, <<"V">>}],
          clock: clock,
          rng: rng,
          stdin: stdin,
          clock_res: clock_res
        })

      assert :wa_wasi_ctx.stdout(ctx) == sink
      assert :wa_wasi_ctx.stderr(ctx) == :collect
      assert :wa_wasi_ctx.args(ctx) == [<<"a">>, <<"b">>]
      assert :wa_wasi_ctx.env(ctx) == [{<<"K">>, <<"V">>}]
      assert :wa_wasi_ctx.clock(ctx) == clock
      assert :wa_wasi_ctx.rng(ctx) == rng
      assert :wa_wasi_ctx.stdin(ctx) == stdin
      assert :wa_wasi_ctx.clock_res(ctx) == clock_res
    end

    test "malformed fields raise {badarg, {wa_wasi_ctx, Field}}" do
      # erlang:error({badarg, _}) surfaces in Elixir as an ArgumentError whose
      # raised term is the tagged tuple; assert on the term for precision.
      assert {:badarg, {:wa_wasi_ctx, :args}} =
               catch_error(:wa_wasi_ctx.new(%{args: [<<"ok">>, 123]}))

      assert {:badarg, {:wa_wasi_ctx, :env}} =
               catch_error(:wa_wasi_ctx.new(%{env: [{<<"K">>, :notbin}]}))

      assert {:badarg, {:wa_wasi_ctx, :sink}} = catch_error(:wa_wasi_ctx.new(%{stdout: :bogus}))

      assert {:badarg, {:wa_wasi_ctx, :clock}} =
               catch_error(:wa_wasi_ctx.new(%{clock: {:fixed, 1}}))

      assert {:badarg, {:wa_wasi_ctx, :rng}} = catch_error(:wa_wasi_ctx.new(%{rng: 42}))

      # preview1-nonfs-completion: new capability shape validation (Req 2.4, 3.4)
      assert {:badarg, {:wa_wasi_ctx, :stdin}} =
               catch_error(:wa_wasi_ctx.new(%{stdin: <<"raw">>}))

      assert {:badarg, {:wa_wasi_ctx, :clock_res}} =
               catch_error(:wa_wasi_ctx.new(%{clock_res: {:fixed, -1, 2}}))
    end
  end

  describe "sink_for/2 and require_sink/2 (Req 4.8, 3.7, 1.5)" do
    test "fd 1/2 resolve to stdout/stderr; other fds are ebadf" do
      ctx = :wa_wasi_ctx.new(%{stdout: :collect, stderr: {:pid, self()}})
      assert :wa_wasi_ctx.sink_for(ctx, 1) == {:ok, :collect}
      assert :wa_wasi_ctx.sink_for(ctx, 2) == {:ok, {:pid, self()}}
      assert :wa_wasi_ctx.sink_for(ctx, 0) == {:error, :ebadf}
      assert :wa_wasi_ctx.sink_for(ctx, 3) == {:error, :ebadf}
    end

    test "require_sink distinguishes bad fd from a missing (unconfigured) sink" do
      # stdout configured, stderr not
      ctx = :wa_wasi_ctx.new(%{stdout: :collect})
      assert :wa_wasi_ctx.require_sink(ctx, 1) == {:ok, :collect}
      # fd 2 valid but no stderr sink -> missing capability, not a host fallback
      assert :wa_wasi_ctx.require_sink(ctx, 2) ==
               {:error, {:missing_capability, {:sink, 2}}}

      # fd outside {1,2} -> ebadf
      assert :wa_wasi_ctx.require_sink(ctx, 5) == {:error, :ebadf}
    end
  end

  describe "require_clock/1 and require_rng/1 (Req 3.4, 3.5, 3.7, 1.5)" do
    test "absent clock/rng reject with a missing-capability error (no host fallback)" do
      ctx = :wa_wasi_ctx.new(%{})
      assert :wa_wasi_ctx.require_clock(ctx) == {:error, {:missing_capability, :clock}}
      assert :wa_wasi_ctx.require_rng(ctx) == {:error, {:missing_capability, :rng}}
    end

    test "configured clock/rng resolve to their source" do
      ctx = :wa_wasi_ctx.new(%{clock: {:fixed, 7, 9}, rng: {:fixed, <<0xAB>>}})
      assert :wa_wasi_ctx.require_clock(ctx) == {:ok, {:fixed, 7, 9}}
      assert :wa_wasi_ctx.require_rng(ctx) == {:ok, {:fixed, <<0xAB>>}}
    end
  end

  # Feature: preview1-nonfs-completion — the two new capabilities.
  # Validates: Requirements 2.2, 2.3, 2.5, 2.6, 3.2, 3.3, 3.5, 3.6, 3.7.
  describe "require_clock_res/1 and require_stdin/1 (Req 2.6, 3.6)" do
    test "absent clock_res/stdin reject with a missing-capability error (no host fallback)" do
      ctx = :wa_wasi_ctx.new(%{})

      assert :wa_wasi_ctx.require_clock_res(ctx) ==
               {:error, {:missing_capability, :clock_res}}

      assert :wa_wasi_ctx.require_stdin(ctx) == {:error, {:missing_capability, :stdin}}
    end

    test "configured clock_res/stdin resolve to their source (fixed and fun shapes)" do
      f = fn _kind -> 5 end
      g = fn max -> {binary_part(<<"abc">>, 0, min(max, 3)), {:fixed, <<>>}} end

      ctx = :wa_wasi_ctx.new(%{clock_res: {:fixed, 1000, 1}, stdin: {:fixed, <<"in">>}})
      assert :wa_wasi_ctx.require_clock_res(ctx) == {:ok, {:fixed, 1000, 1}}
      assert :wa_wasi_ctx.require_stdin(ctx) == {:ok, {:fixed, <<"in">>}}

      ctx2 = :wa_wasi_ctx.new(%{clock_res: {:fun, f}, stdin: {:fun, g}})
      assert {:ok, {:fun, ^f}} = :wa_wasi_ctx.require_clock_res(ctx2)
      assert {:ok, {:fun, ^g}} = :wa_wasi_ctx.require_stdin(ctx2)
    end
  end

  describe "opt-in host-backed helpers do not read the host at construction (Req 3.4, 3.5)" do
    test "host_clock/0 returns a fun source; crypto_rng/0 returns the crypto tag" do
      assert {:fun, f} = :wa_wasi_ctx.host_clock()
      assert is_function(f, 1)
      # invoking it yields integers (nanoseconds), but new/1 never calls it
      assert is_integer(f.(:realtime))
      assert is_integer(f.(:monotonic))

      assert :wa_wasi_ctx.crypto_rng() == :crypto
    end
  end
end
