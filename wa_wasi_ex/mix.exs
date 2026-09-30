defmodule WaWasiEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/couchemar/wa_wasi"

  def project do
    [
      app: :wa_wasi_ex,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "WaWasiEx",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Test support modules (the binary-backed accessor + the wa_embedder memory
  # adapter) live under test/support and only compile in the test env.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # The Erlang core (`:wa_wasi`) is a separate hex package built with rebar3.
  # Locally it lives in the parent directory (the repo root); set WA_WASI_PATH
  # (the dev shell sets it to "..") to build against the sibling source instead
  # of the published release.
  #
  # `wa_embedder_ex` is a TEST-ONLY dependency: the end-to-end tests compile and
  # run real WASM modules through it to exercise the WASI host functions. It is
  # excluded from the shipped package; the core `wa_wasi` depends on neither
  # `wa_embedder` nor `wa_embedder_ex`.
  defp deps do
    core =
      case System.get_env("WA_WASI_PATH") do
        nil -> {:wa_wasi, "~> 0.1"}
        path -> {:wa_wasi, path: path, manager: :rebar3, override: true}
      end

    [
      core,
      {:wa_embedder_ex, "~> 0.2", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Idiomatic Elixir wrapper over the wa_wasi WASI preview1 host-function " <>
      "library (the Erlang :wa_wasi core). Builds a wasi_snapshot_preview1 " <>
      "import map for a memory accessor and a capabilities context."
  end

  defp package do
    [
      licenses: ["Unlicense"],
      links: %{
        "GitHub" => @source_url,
        "Core (Erlang)" => "https://hex.pm/packages/wa_wasi"
      },
      files: ~w(lib mix.exs README.md UNLICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "UNLICENSE"]
    ]
  end
end
