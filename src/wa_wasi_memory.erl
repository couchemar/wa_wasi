%% The `Wa_Wasi_Memory' behaviour: wa_wasi's minimal byte-level contract for a
%% WASM module's linear memory.
%%
%% A compiled host function receives only the WASM integer operands — never a
%% handle to linear memory. To read/write that memory without depending on any
%% particular WASM runtime, wa_wasi parameterizes every host function by a
%% Memory_Accessor: a `{Module, Handle}' pair where `Module' implements this
%% behaviour and `Handle' is opaque backend state. The caller supplies the
%% accessor (e.g. an adapter over their runtime's memory); wa_wasi only ever
%% calls `read_bytes/3' / `write_bytes/3'.
%%
%% Pure Erlang: OTP + wa_wasi_* only (no `'Elixir.*'', no `wa_embedder*'').
-module(wa_wasi_memory).

%% Opaque, backend-specific memory handle. Exported so it can appear in the
%% public -callback signatures without a dialyzer/ex_doc "private type" warning.
-type handle() :: term().
-export_type([handle/0, accessor/0]).

%% A Memory_Accessor is a {Module, Handle} pair: Module implements this
%% behaviour; Handle is opaque state passed back on every call.
-type accessor() :: {module(), handle()}.

%% Read `Len' bytes starting at `Offset'. Returns the exact bytes, or
%% `{error, efault}' if the range is outside the module's linear memory.
-callback read_bytes(Handle :: handle(),
                     Offset :: non_neg_integer(),
                     Len :: non_neg_integer()) ->
    {ok, binary()} | {error, efault}.

%% Write `Bytes' starting at `Offset'. Returns `ok', or `{error, efault}' if
%% the range is outside bounds (in which case memory must be left unmodified —
%% no partial write).
-callback write_bytes(Handle :: handle(),
                      Offset :: non_neg_integer(),
                      Bytes :: binary()) ->
    ok | {error, efault}.

%% Bounded helpers used by every host function. They guard the preconditions the
%% behaviour promises (non-negative offset/len) before dispatching, and
%% normalize the accessor's result.
-export([read/3, write/3]).

%% Read exactly `Len' bytes at `Offset'. A negative offset or length is an
%% out-of-bounds access (`{error, efault}'). A short read (fewer bytes than
%% requested) is likewise treated as out-of-bounds, so callers can rely on the
%% returned binary being exactly `Len' bytes on success (Req 2.2, 2.4, 2.5).
-spec read(accessor(), integer(), integer()) -> {ok, binary()} | {error, efault}.
read(_Accessor, Offset, Len) when Offset < 0; Len < 0 ->
    {error, efault};
read({Mod, Handle}, Offset, Len) ->
    case Mod:read_bytes(Handle, Offset, Len) of
        {ok, Bytes} when byte_size(Bytes) =:= Len -> {ok, Bytes};
        {ok, _Short} -> {error, efault};
        {error, efault} = E -> E
    end.

%% Write `Bytes' at `Offset'. A negative offset is out-of-bounds
%% (`{error, efault}'); otherwise dispatch to the accessor, which bounds-checks
%% and must not partially write on failure (Req 2.3, 2.5).
-spec write(accessor(), integer(), binary()) -> ok | {error, efault}.
write(_Accessor, Offset, _Bytes) when Offset < 0 ->
    {error, efault};
write({Mod, Handle}, Offset, Bytes) when is_binary(Bytes) ->
    Mod:write_bytes(Handle, Offset, Bytes).
