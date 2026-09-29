%% WASI preview1 host-function implementations for the wa_wasi library.
%%
%% This module holds the errno constants, the pure little-endian codec helpers
%% shared by every host function, and (added in later tasks) the host-function
%% bodies themselves. It is pure Erlang: only OTP + wa_wasi_* modules, never an
%% `'Elixir.*'' module and never any `wa_embedder*' module.
%%
%% WASI preview1 numeric contract (encoded here):
%%   * pointers and sizes are i32; multi-byte values in linear memory are
%%     little-endian.
%%   * an `iovec' is an 8-byte record `{buf: u32, buf_len: u32}'.
%%   * timestamps are i64 nanoseconds.
%%   * every function (except proc_exit) returns an i32 errno (0 = success).
-module(wa_wasi_preview1).

%% Pure codec helpers (shared by every host function).
-export([encode_u32/1, decode_u32/1, encode_u64/1, decode_iovecs/1]).

%% Errno constants exported as 0-arity functions so callers/tests can name them
%% without duplicating the literals. The macros below are used internally.
-export([esuccess/0, ebadf/0, einval/0, efault/0]).

%% Host functions (more are added in later tasks).
-export([fd_write/6]).

%% Test/inspection helper: bytes accumulated by a `collect' sink in this
%% process, per fd. Not part of the WASI ABI.
-export([collected/1]).

%% --------------------------------------------------------------------------
%% Errno constants (WASI preview1 `errno' variant, position-indexed).
%% Values verified against the preview1 witx enumeration:
%%   success = 0, badf = 8, fault = 21, inval = 28.
%% --------------------------------------------------------------------------
-define(ESUCCESS, 0).
-define(EBADF, 8).
-define(EINVAL, 28).
-define(EFAULT, 21).

-spec esuccess() -> 0.
esuccess() -> ?ESUCCESS.

-spec ebadf() -> 8.
ebadf() -> ?EBADF.

-spec einval() -> 28.
einval() -> ?EINVAL.

-spec efault() -> 21.
efault() -> ?EFAULT.

%% --------------------------------------------------------------------------
%% Little-endian codec helpers (pure).
%%
%% All WASI preview1 values in linear memory are little-endian, with the
%% least-significant byte at the lowest offset.
%% --------------------------------------------------------------------------

%% Encode a 32-bit unsigned integer as 4 little-endian bytes.
-spec encode_u32(0..4294967295) -> binary().
encode_u32(V) when is_integer(V), V >= 0, V =< 16#FFFFFFFF ->
    <<V:32/little-unsigned>>.

%% Decode 4 little-endian bytes as a 32-bit unsigned integer.
-spec decode_u32(binary()) -> 0..4294967295.
decode_u32(<<V:32/little-unsigned>>) ->
    V.

%% Encode a signed 64-bit integer as 8 little-endian bytes. Used for the i64
%% nanosecond timestamp written by clock_time_get; a `signed' field accepts the
%% full i64 range while still round-tripping unsigned values that fit.
-spec encode_u64(integer()) -> binary().
encode_u64(V) when is_integer(V) ->
    <<V:64/little-signed>>.

%% Decode a contiguous array of 8-byte little-endian iovec records into a list
%% of `{BufPtr, BufLen}' pairs, in ascending order. Each iovec is a 4-byte
%% little-endian buffer pointer followed by a 4-byte little-endian buffer
%% length. The input binary length must be a multiple of 8.
-spec decode_iovecs(binary()) -> [{0..4294967295, 0..4294967295}].
decode_iovecs(<<>>) ->
    [];
decode_iovecs(<<Ptr:32/little-unsigned, Len:32/little-unsigned, Rest/binary>>) ->
    [{Ptr, Len} | decode_iovecs(Rest)].

%% --------------------------------------------------------------------------
%% fd_write (Req 4)
%%
%% Signature: (Accessor, Ctx, Fd, IovsPtr, IovsLen, NwrittenPtr) -> Errno.
%% Reads `IovsLen' 8-byte iovec records at `IovsPtr', reads each referenced
%% buffer, concatenates them in ascending index order, emits the result to the
%% fd's configured sink (fd 1 = stdout, fd 2 = stderr), and writes the total
%% byte count as a u32 at `NwrittenPtr'.
%%
%% Atomicity (compute-then-write, fail atomically): all memory reads happen and
%% the full output binary is built first; the Nwritten pointer is confirmed
%% writable (by actually writing the count) BEFORE the sink is touched. The sink
%% emission is the one non-undoable side effect, so it is sequenced last — on
%% any EFAULT nothing is written to the sink and linear memory is unmodified
%% (Req 4.9).
%% --------------------------------------------------------------------------
-spec fd_write(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
               integer(), integer(), integer(), integer()) -> integer().
fd_write(Accessor, Ctx, Fd, IovsPtr, IovsLen, NwrittenPtr) ->
    case wa_wasi_ctx:require_sink(Ctx, Fd) of
        {error, ebadf} ->
            %% fd not in {1,2}: touch nothing (Req 4.8)
            ?EBADF;
        {error, {missing_capability, _} = Reason} ->
            %% valid fd but no sink configured: fail loud, no host fallback
            %% (Req 3.7, 1.5).
            erlang:error(Reason);
        {ok, Sink} ->
            fd_write_1(Accessor, Fd, Sink, IovsPtr, IovsLen, NwrittenPtr)
    end.

%% IovsLen == 0: write 0 to Nwritten, no sink write (Req 4.6).
fd_write_1(Accessor, _Fd, _Sink, _IovsPtr, 0, NwrittenPtr) ->
    case wa_wasi_memory:write(Accessor, NwrittenPtr, encode_u32(0)) of
        ok -> ?ESUCCESS;
        {error, efault} -> ?EFAULT
    end;
fd_write_1(Accessor, Fd, Sink, IovsPtr, IovsLen, NwrittenPtr) ->
    %% (a) read the iovec array (IovsLen * 8 bytes)
    case wa_wasi_memory:read(Accessor, IovsPtr, IovsLen * 8) of
        {error, efault} ->
            ?EFAULT;
        {ok, IovBin} ->
            Iovecs = decode_iovecs(IovBin),
            %% (b) read each buffer in ascending index order and concatenate
            case gather(Accessor, Iovecs) of
                {error, efault} ->
                    ?EFAULT;
                {ok, Buf} ->
                    %% (c) confirm Nwritten writable BEFORE touching the sink
                    NW = byte_size(Buf),
                    case wa_wasi_memory:write(Accessor, NwrittenPtr, encode_u32(NW)) of
                        {error, efault} ->
                            ?EFAULT;
                        ok ->
                            %% (d) emit last — the only non-undoable effect
                            emit(Sink, Fd, Buf),
                            ?ESUCCESS
                    end
            end
    end.

%% Read and concatenate every iovec buffer; any OOB -> {error, efault}.
gather(Accessor, Iovecs) ->
    gather(Accessor, Iovecs, <<>>).

gather(_Accessor, [], Acc) ->
    {ok, Acc};
gather(Accessor, [{Ptr, Len} | Rest], Acc) ->
    case wa_wasi_memory:read(Accessor, Ptr, Len) of
        {ok, Bytes} -> gather(Accessor, Rest, <<Acc/binary, Bytes/binary>>);
        {error, efault} = E -> E
    end.

%% Deliver output bytes to a resolved sink.
%%   {fun, F} — call F(Bytes)
%%   collect  — append to this process's per-fd accumulator (read via collected/1)
%%   {pid, P} — send {wa_wasi_output, Fd, Bytes} to P
emit(_Sink, _Fd, <<>>) ->
    %% nothing to emit
    ok;
emit({'fun', F}, _Fd, Bytes) ->
    _ = F(Bytes),
    ok;
emit(collect, Fd, Bytes) ->
    Key = {wa_wasi_collected, Fd},
    Prev =
        case get(Key) of
            undefined -> <<>>;
            B when is_binary(B) -> B
        end,
    put(Key, <<Prev/binary, Bytes/binary>>),
    ok;
emit({pid, P}, Fd, Bytes) ->
    P ! {wa_wasi_output, Fd, Bytes},
    ok.

%% Read the bytes accumulated by a `collect' sink for `Fd' in this process.
-spec collected(integer()) -> binary().
collected(Fd) ->
    case get({wa_wasi_collected, Fd}) of
        undefined -> <<>>;
        B when is_binary(B) -> B
    end.
