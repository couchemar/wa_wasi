# Builds the WAT test fixtures (wat/*.wat -> wat/*.wasm via wat2wasm) through
# CMake/Ninja before the suite runs, then starts ExUnit.
#
# Tolerant by design (per the plan): the pure accessor-level (Layer-a) unit
# tests need NO fixtures, so a missing toolchain or an empty wat/ directory is
# NOT fatal — we skip the build and still start ExUnit. Only the end-to-end
# (Layer-b) WAT tests require the fixtures; those are the ones that will fail
# loudly if the build was skipped.

fixture_dir = Path.expand("../../test_data", __DIR__)
build_dir = Path.join(fixture_dir, "build")
wat_dir = Path.join(fixture_dir, "wat")

wat_files = Path.wildcard(Path.join(wat_dir, "*.wat"))
have_tools? = Enum.all?(["cmake", "ninja"], &System.find_executable/1)

cond do
  wat_files == [] ->
    IO.puts("[wa_wasi tests] no WAT fixtures yet; skipping fixture build (unit tests only)")

  not have_tools? ->
    IO.puts(
      "[wa_wasi tests] cmake/ninja not found; skipping fixture build. " <>
        "Enter the Nix dev shell (`nix develop`) to run the end-to-end WAT tests."
    )

  true ->
    unless File.exists?(Path.join(build_dir, "build.ninja")) do
      case System.cmd("cmake", ["-S", fixture_dir, "-B", build_dir, "-G", "Ninja"],
             stderr_to_stdout: true
           ) do
        {_, 0} ->
          :ok

        {output, code} ->
          raise "cmake configure failed for test fixtures (exit #{code}):\n#{output}"
      end
    end

    case System.cmd("ninja", ["-C", build_dir], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> raise "ninja failed building test fixtures (exit #{code}):\n#{output}"
    end
end

ExUnit.start()
