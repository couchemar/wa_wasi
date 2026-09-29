defmodule WaWasi.TestMemory do
  @moduledoc """
  A binary-backed `:wa_wasi_memory` accessor for the pure (Layer-a) unit tests.

  Holds a WASM module's linear memory as a fixed-size mutable binary in an
  Agent, so `write_bytes/3` persists across calls without a real WASM runtime.
  This lets the host-function and accessor tests run fast with no `wa_embedder`
  dependency.

  Usage:

      handle = WaWasi.TestMemory.new(64)                 # 64 zero bytes
      handle = WaWasi.TestMemory.new(<<1, 2, 3, ...>>)   # known contents
      acc = {WaWasi.TestMemory, handle}                  # a Memory_Accessor
      {:ok, bytes} = :wa_wasi_memory.read(acc, 0, 4)
      WaWasi.TestMemory.dump(handle)                     # inspect full memory

  Out-of-bounds reads/writes return `{:error, :efault}` and leave memory
  unmodified — matching the `:wa_wasi_memory` behaviour contract.
  """

  @behaviour :wa_wasi_memory

  @doc "New handle from a byte size (zero-filled) or explicit initial contents."
  def new(size) when is_integer(size) and size >= 0, do: new(<<0::size(size)-unit(8)>>)

  def new(bin) when is_binary(bin) do
    {:ok, pid} = Agent.start_link(fn -> bin end)
    pid
  end

  @doc "Return the full current memory contents (test inspection helper)."
  def dump(pid), do: Agent.get(pid, & &1)

  @doc "Current memory size in bytes."
  def size(pid), do: byte_size(Agent.get(pid, & &1))

  @impl :wa_wasi_memory
  def read_bytes(pid, offset, len)
      when is_integer(offset) and offset >= 0 and is_integer(len) and len >= 0 do
    mem = Agent.get(pid, & &1)

    if offset + len <= byte_size(mem) do
      {:ok, binary_part(mem, offset, len)}
    else
      {:error, :efault}
    end
  end

  def read_bytes(_pid, _offset, _len), do: {:error, :efault}

  @impl :wa_wasi_memory
  def write_bytes(pid, offset, bytes)
      when is_integer(offset) and offset >= 0 and is_binary(bytes) do
    Agent.get_and_update(pid, fn mem ->
      len = byte_size(bytes)

      if offset + len <= byte_size(mem) do
        before = binary_part(mem, 0, offset)
        rest = binary_part(mem, offset + len, byte_size(mem) - offset - len)
        {:ok, <<before::binary, bytes::binary, rest::binary>>}
      else
        # out of bounds: leave memory unmodified
        {{:error, :efault}, mem}
      end
    end)
  end

  def write_bytes(_pid, _offset, _bytes), do: {:error, :efault}
end
