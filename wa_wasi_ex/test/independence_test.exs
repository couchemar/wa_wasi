defmodule WaWasi.IndependenceTest do
  use ExUnit.Case, async: true

  # Feature: wasi-preview1 — Independence Invariant (structural SMOKE test).
  # Validates: Requirements 1.2, 1.3, 11.1.
  #
  # The Erlang core must depend only on OTP + its own wa_wasi_* modules: it may
  # NOT reference any 'Elixir.*' module and may NOT reference any wa_embedder
  # module. This scans every src/*.erl of the core (the repo root, one level up
  # from wa_wasi_ex/) for the forbidden substrings.

  # wa_wasi_ex/test -> repo root is two levels up.
  @core_src Path.expand("../../src", __DIR__)

  test "the Erlang core exists and has source files" do
    assert File.dir?(@core_src), "expected core src dir at #{@core_src}"
    assert Path.wildcard(Path.join(@core_src, "*.erl")) != []
  end

  test "no src/*.erl references an 'Elixir.' module or any wa_embedder module" do
    for path <- Path.wildcard(Path.join(@core_src, "*.erl")) do
      code = code_only(File.read!(path))
      base = Path.basename(path)

      refute String.contains?(code, "'Elixir."),
             "#{base} references an 'Elixir.*' module (Independence Invariant, Req 1.3)"

      refute String.contains?(code, "wa_embedder"),
             "#{base} references wa_embedder (Independence Invariant, Req 1.2)"
    end
  end

  # Strip Erlang comments so the scan checks CODE, not documentation prose that
  # legitimately mentions the invariant (e.g. "no 'Elixir.*', no wa_embedder*").
  # Erlang line comments start at `%` and run to end of line; our sources have
  # no `%` inside string/atom literals.
  defp code_only(contents) do
    contents
    |> String.split("\n")
    |> Enum.map(fn line -> line |> String.split("%", parts: 2) |> hd() end)
    |> Enum.join("\n")
  end
end
