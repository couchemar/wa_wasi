defmodule WaWasi.EmbedderMemoryAdapter do
  @moduledoc """
  A TEST-ONLY `:wa_wasi_memory` accessor bridging wa_wasi to a `wa_embedder`-
  compiled module's linear memory.

  This is exactly the "user supplies the glue" adapter the design calls for: it
  lives in the test tree (never in the shipped `wa_wasi` core), and it is the
  only component that knows about `wa_embedder`'s runtime memory representation.

  A `wa_embedder`-compiled module keeps its linear-memory reference in the
  CALLING process's dictionary under `{:__wasm_mem, ModuleName, 0}` (memory
  index 0). The reference is the opaque backend map `%{mem: binary, max: ...}`.

  Reads slice `ref.mem` directly (the published `wa_embedder_memory_binary`
  exposes `write_data/3` for writes but not a public byte-`read/3`, so we read
  from the ref's binary ourselves with our own bounds check). Writes go through
  `write_data/3`, storing the returned new reference back in the process dict.
  Out-of-bounds access on either side yields `{:error, :efault}`, matching the
  `:wa_wasi_memory` contract.

  Usage:

      acc = {WaWasi.EmbedderMemoryAdapter, module_name}
      imports = WaWasi.imports(acc, ctx)
  """

  @behaviour :wa_wasi_memory

  @doc "A Memory_Accessor for a compiled module (memory index 0)."
  def accessor(module) when is_atom(module), do: {__MODULE__, module}

  @impl :wa_wasi_memory
  def read_bytes(module, offset, len)
      when is_atom(module) and is_integer(offset) and offset >= 0 and
             is_integer(len) and len >= 0 do
    %{mem: mem} = ref(module)

    if offset + len <= byte_size(mem) do
      {:ok, binary_part(mem, offset, len)}
    else
      {:error, :efault}
    end
  end

  def read_bytes(_module, _offset, _len), do: {:error, :efault}

  @impl :wa_wasi_memory
  def write_bytes(module, offset, bytes)
      when is_atom(module) and is_integer(offset) and offset >= 0 and is_binary(bytes) do
    %{mem: mem} = r = ref(module)

    if offset + byte_size(bytes) <= byte_size(mem) do
      new_ref = :wa_embedder_memory_binary.write_data(r, offset, bytes)
      :erlang.put(pd_key(module), new_ref)
      :ok
    else
      {:error, :efault}
    end
  end

  def write_bytes(_module, _offset, _bytes), do: {:error, :efault}

  # The compiled module's linear-memory reference for memory index 0.
  defp ref(module), do: :erlang.get(pd_key(module))

  defp pd_key(module), do: {:__wasm_mem, module, 0}
end
