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
-export([encode_u32/1, decode_u32/1, encode_u64/1, encode_u16/1, decode_iovecs/1]).

%% Errno constants exported as 0-arity functions so callers/tests can name them
%% without duplicating the literals. The macros below are used internally.
-export([esuccess/0, ebadf/0, einval/0, efault/0]).

%% Host functions (more are added in later tasks).
-export([fd_write/6, args_sizes_get/4, environ_sizes_get/4, args_get/4, environ_get/4]).
-export([clock_time_get/5, random_get/4]).
-export([proc_exit/2]).
%% Non-filesystem preview1 completion.
-export([clock_res_get/4, sched_yield/1, fd_fdstat_get/4, fd_read/6]).

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

%% --------------------------------------------------------------------------
%% Fdstat / Rights / Filetype constants (WASI preview1). These are struct field
%% values, NOT errnos — no new errno constant is introduced. Used by
%% fd_fdstat_get (added in a later task) so no bare integer literals appear in
%% the function bodies.
%% --------------------------------------------------------------------------
%% `filetype' code reported for the standard fds (stdin/stdout/stderr).
-define(FILETYPE_CHARACTER_DEVICE, 2).

%% `fdflags' u16 bitfield value reported for the standard fds (no flags set).
-define(FDFLAGS_NONE, 0).

%% `rights' u64 bitfield bits: fd_read is bit 1, fd_write is bit 6.
-define(RIGHTS_FD_READ, (1 bsl 1)).
-define(RIGHTS_FD_WRITE, (1 bsl 6)).
-define(RIGHTS_NONE, 0).

%% The `fdstat' struct is 24 bytes, 8-byte aligned.
-define(FDSTAT_SIZE, 24).

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

%% Encode a 16-bit unsigned integer as 2 little-endian bytes. Used for the
%% `fdflags' field of the fdstat struct written by fd_fdstat_get.
-spec encode_u16(0..65535) -> binary().
encode_u16(V) when is_integer(V), V >= 0, V =< 16#FFFF ->
    <<V:16/little-unsigned>>.

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

%% --------------------------------------------------------------------------
%% args_sizes_get / environ_sizes_get (Req 5.1-5.2, 5.5, 5.6; 6.1-6.2, 6.5, 6.6)
%%
%% Both report two values into caller memory: the item count and the total byte
%% size of the NUL-terminated item strings (sum over items of byte_size + 1).
%% args items are the raw arg binaries; environ items are formatted `KEY=VALUE'.
%% An empty list reports 0 / 0.
%%
%% Atomicity across two disjoint u32 pointers: probe both destination ranges
%% (a bounded read) before writing either; if either probe is OOB, return
%% EFAULT with memory unmodified (Req 5.6, 6.6).
%% --------------------------------------------------------------------------
-spec args_sizes_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                     integer(), integer()) -> integer().
args_sizes_get(Accessor, Ctx, CountPtr, BufSizePtr) ->
    sizes_get(Accessor, wa_wasi_ctx:args(Ctx), CountPtr, BufSizePtr).

-spec environ_sizes_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                        integer(), integer()) -> integer().
environ_sizes_get(Accessor, Ctx, CountPtr, BufSizePtr) ->
    sizes_get(Accessor, env_items(Ctx), CountPtr, BufSizePtr).

sizes_get(Accessor, Items, CountPtr, BufSizePtr) ->
    Count = length(Items),
    BufSize = lists:sum([byte_size(I) + 1 || I <- Items]),
    %% Probe both 4-byte destinations before writing either (all-or-nothing).
    case {probe(Accessor, CountPtr, 4), probe(Accessor, BufSizePtr, 4)} of
        {ok, ok} ->
            ok = wa_wasi_memory:write(Accessor, CountPtr, encode_u32(Count)),
            ok = wa_wasi_memory:write(Accessor, BufSizePtr, encode_u32(BufSize)),
            ?ESUCCESS;
        _ ->
            ?EFAULT
    end.

%% Environment entries formatted as `KEY=VALUE' binaries (Req 6.2/6.4).
env_items(Ctx) ->
    [<<K/binary, $=, V/binary>> || {K, V} <- wa_wasi_ctx:env(Ctx)].

%% Confirm a destination range is writable by attempting a bounded read of the
%% same range (reuses the accessor's own bounds check without needing to know
%% the memory size). Returns `ok' | `{error, efault}'.
probe(Accessor, Ptr, Len) ->
    case wa_wasi_memory:read(Accessor, Ptr, Len) of
        {ok, _} -> ok;
        {error, efault} -> {error, efault}
    end.

%% --------------------------------------------------------------------------
%% args_get / environ_get (Req 5.3-5.4, 5.5, 5.6; 6.3-6.4, 6.5, 6.6)
%%
%% Write two regions: the NUL-terminated string buffer (each item followed by a
%% NUL) at `BufPtr', and the pointer array at `PtrArrayPtr' — one u32 per item
%% giving the linear-memory address of that item's string (`BufPtr' + the
%% item's running offset within the buffer). args items are the raw arg
%% binaries; environ items are `KEY=VALUE'. Items are written in configuration
%% order. An empty list writes nothing and succeeds.
%%
%% Atomicity across the two disjoint regions: probe both destination ranges
%% before writing either; OOB in either -> EFAULT, memory unmodified
%% (Req 5.6, 6.6).
%% --------------------------------------------------------------------------
-spec args_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
               integer(), integer()) -> integer().
args_get(Accessor, Ctx, PtrArrayPtr, BufPtr) ->
    get_items(Accessor, wa_wasi_ctx:args(Ctx), PtrArrayPtr, BufPtr).

-spec environ_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                  integer(), integer()) -> integer().
environ_get(Accessor, Ctx, PtrArrayPtr, BufPtr) ->
    get_items(Accessor, env_items(Ctx), PtrArrayPtr, BufPtr).

%% Empty list: nothing to write, success (the pointer array and buffer are both
%% zero-length, Req 5.5/6.5).
get_items(_Accessor, [], _PtrArrayPtr, _BufPtr) ->
    ?ESUCCESS;
get_items(Accessor, Items, PtrArrayPtr, BufPtr) ->
    %% Build the NUL-terminated string buffer and the pointer array together,
    %% tracking each item's running offset so pointer N = BufPtr + Offset_N.
    {Buf, PtrArray} = build_get_regions(Items, BufPtr),
    %% Probe both destinations before writing either (all-or-nothing).
    case {probe(Accessor, PtrArrayPtr, byte_size(PtrArray)),
          probe(Accessor, BufPtr, byte_size(Buf))} of
        {ok, ok} ->
            ok = wa_wasi_memory:write(Accessor, PtrArrayPtr, PtrArray),
            ok = wa_wasi_memory:write(Accessor, BufPtr, Buf),
            ?ESUCCESS;
        _ ->
            ?EFAULT
    end.

%% Returns {StringBuffer, PointerArray}. StringBuffer is each item followed by a
%% NUL byte, concatenated in order. PointerArray is `4 * length(Items)' bytes,
%% each a u32 = BufPtr + the item's byte offset within StringBuffer.
build_get_regions(Items, BufPtr) ->
    build_get_regions(Items, BufPtr, 0, <<>>, <<>>).

build_get_regions([], _BufPtr, _Off, Buf, Ptrs) ->
    {Buf, Ptrs};
build_get_regions([Item | Rest], BufPtr, Off, Buf, Ptrs) ->
    Ptr = encode_u32(BufPtr + Off),
    Entry = <<Item/binary, 0>>,
    build_get_regions(
        Rest,
        BufPtr,
        Off + byte_size(Entry),
        <<Buf/binary, Entry/binary>>,
        <<Ptrs/binary, Ptr/binary>>
    ).

%% --------------------------------------------------------------------------
%% clock_time_get (Req 7)
%%
%% Signature: (Accessor, Ctx, ClockId, Precision, TimePtr) -> Errno.
%% ClockId 0 = realtime, 1 = monotonic; any other id -> EINVAL, write nothing
%% (Req 7.4). `Precision' is accepted and ignored — the value comes only from
%% the configured clock source (Req 3.4). Writes the nanosecond timestamp as an
%% 8-byte little-endian signed i64 at `TimePtr'; OOB -> EFAULT, no bytes written
%% (Req 7.5).
%% --------------------------------------------------------------------------
-spec clock_time_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                     integer(), integer(), integer()) -> integer().
clock_time_get(Accessor, Ctx, ClockId, _Precision, TimePtr) ->
    case clock_kind(ClockId) of
        {error, einval} ->
            ?EINVAL;
        {ok, Kind} ->
            case wa_wasi_ctx:require_clock(Ctx) of
                {error, {missing_capability, _} = Reason} ->
                    erlang:error(Reason);
                {ok, Source} ->
                    Ns = clock_ns(Source, Kind),
                    case wa_wasi_memory:write(Accessor, TimePtr, encode_u64(Ns)) of
                        ok -> ?ESUCCESS;
                        {error, efault} -> ?EFAULT
                    end
            end
    end.

clock_kind(0) -> {ok, realtime};
clock_kind(1) -> {ok, monotonic};
clock_kind(_) -> {error, einval}.

%% Obtain the nanosecond value for `Kind' from the configured clock source.
clock_ns({'fun', F}, Kind) -> F(Kind);
clock_ns({fixed, Rt, _Mono}, realtime) -> Rt;
clock_ns({fixed, _Rt, Mono}, monotonic) -> Mono.

%% --------------------------------------------------------------------------
%% clock_res_get (Req 4)
%%
%% Signature: (Accessor, Ctx, ClockId, ResPtr) -> Errno.
%% ClockId 0 = realtime, 1 = monotonic; any other id (incl. 2 process_cputime_id
%% and 3 thread_cputime_id) -> EINVAL, write nothing (Req 4.4). Writes the
%% configured clock RESOLUTION in nanoseconds as an 8-byte little-endian u64 at
%% `ResPtr'; OOB -> EFAULT, no bytes written (Req 4.5). The resolution comes only
%% from the Clock_Resolution_Source in the context; an absent source raises
%% {missing_capability, clock_res} (Req 4.6, no host fallback) — mirroring
%% clock_time_get, since WASI has no errno for an unwired clock.
%% --------------------------------------------------------------------------
-spec clock_res_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                    integer(), integer()) -> integer().
clock_res_get(Accessor, Ctx, ClockId, ResPtr) ->
    case clock_kind(ClockId) of
        {error, einval} ->
            ?EINVAL;
        {ok, Kind} ->
            case wa_wasi_ctx:require_clock_res(Ctx) of
                {error, {missing_capability, _} = Reason} ->
                    erlang:error(Reason);
                {ok, Source} ->
                    Res = clock_res_ns(Source, Kind),
                    case wa_wasi_memory:write(Accessor, ResPtr, encode_u64(Res)) of
                        ok -> ?ESUCCESS;
                        {error, efault} -> ?EFAULT
                    end
            end
    end.

%% Obtain the resolution (ns) for `Kind' from the configured resolution source.
clock_res_ns({'fun', F}, Kind) -> F(Kind);
clock_res_ns({fixed, Rt, _Mono}, realtime) -> Rt;
clock_res_ns({fixed, _Rt, Mono}, monotonic) -> Mono.

%% --------------------------------------------------------------------------
%% random_get (Req 8)
%%
%% Signature: (Accessor, Ctx, BufPtr, BufLen) -> Errno.
%% BufLen == 0 -> no bytes written, ESUCCESS (Req 8.3). Otherwise obtain exactly
%% BufLen bytes from the configured RNG source and write them at BufPtr; OOB ->
%% EFAULT, no bytes written (Req 8.4). The RNG source supplies the bytes — the
%% core never reads host randomness implicitly (Req 3.5).
%%   {fun, F}     -> F(BufLen), asserted to be exactly BufLen bytes
%%   {fixed, Bin} -> Bin cycled/truncated to BufLen deterministic bytes
%%   crypto       -> crypto:strong_rand_bytes(BufLen)
%% --------------------------------------------------------------------------
-spec random_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                 integer(), integer()) -> integer().
random_get(_Accessor, _Ctx, _BufPtr, 0) ->
    ?ESUCCESS;
random_get(Accessor, Ctx, BufPtr, BufLen) when BufLen > 0 ->
    case wa_wasi_ctx:require_rng(Ctx) of
        {error, {missing_capability, _} = Reason} ->
            erlang:error(Reason);
        {ok, Source} ->
            Bytes = rng_bytes(Source, BufLen),
            %% The source must produce exactly BufLen bytes (Req 8.2).
            BufLen = byte_size(Bytes),
            case wa_wasi_memory:write(Accessor, BufPtr, Bytes) of
                ok -> ?ESUCCESS;
                {error, efault} -> ?EFAULT
            end
    end.

%% Produce exactly N bytes from an RNG source.
rng_bytes({'fun', F}, N) ->
    F(N);
rng_bytes({fixed, Bin}, N) ->
    fixed_bytes(Bin, N);
rng_bytes(crypto, N) ->
    crypto:strong_rand_bytes(N).

%% Deterministic N bytes from a fixed seed: cycle the seed and truncate to N.
%% An empty seed with N > 0 has no bytes to cycle — that is a caller error.
fixed_bytes(_Bin, 0) ->
    <<>>;
fixed_bytes(Bin, N) when byte_size(Bin) > 0 ->
    Reps = (N div byte_size(Bin)) + 1,
    Full = binary:copy(Bin, Reps),
    binary:part(Full, 0, N).

%% --------------------------------------------------------------------------
%% proc_exit (Req 9)
%%
%% Signature: (Ctx, Code) -> no_return(). Raises the catchable Erlang error
%% `{wasi_exit, Code}' to unwind the running module without returning a value
%% and WITHOUT terminating the BEAM — never `erlang:halt' (Req 9.2-9.4). `Code'
%% is interpreted unsigned (masked to 32 bits, Req 9.1). The accessor is unused.
%% --------------------------------------------------------------------------
-spec proc_exit(wa_wasi_ctx:t(), integer()) -> no_return().
proc_exit(_Ctx, Code) ->
    erlang:error({wasi_exit, Code band 16#FFFFFFFF}).

%% --------------------------------------------------------------------------
%% sched_yield (Req 5)
%%
%% Signature: (Ctx) -> Errno. A no-op scheduler yield: always returns ESUCCESS,
%% touches no linear memory, and requires no Config_Context capability. The
%% `Ctx' argument is accepted for a uniform call site (mirroring proc_exit) and
%% ignored.
%% --------------------------------------------------------------------------
-spec sched_yield(wa_wasi_ctx:t()) -> integer().
sched_yield(_Ctx) ->
    ?ESUCCESS.

%% --------------------------------------------------------------------------
%% fd_fdstat_get (Req 6)
%%
%% Signature: (Accessor, Ctx, Fd, BufPtr) -> Errno. Writes a 24-byte `fdstat'
%% struct for a KNOWN standard fd at `BufPtr':
%%   fd 1 (stdout) / fd 2 (stderr) -> character_device, fdflags 0, rights
%%     fd_write, inheriting 0 (Req 6.4).
%%   fd 0 (stdin)  -> character_device, fdflags 0, rights fd_read, inheriting 0,
%%     but ONLY when a Stdin_Source is configured; otherwise EBADF (Req 6.5/6.6).
%%   any other fd  -> EBADF, write nothing (Req 6.7).
%% The struct is built as one binary and written via write/3, whose accessor
%% bounds-checks and never partially writes, so OOB -> EFAULT with memory
%% unmodified (Req 6.8).
%% --------------------------------------------------------------------------
-spec fd_fdstat_get(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
                    integer(), integer()) -> integer().
fd_fdstat_get(Accessor, Ctx, Fd, BufPtr) ->
    case fdstat_for(Ctx, Fd) of
        {error, ebadf} ->
            ?EBADF;
        {ok, Struct} ->
            case wa_wasi_memory:write(Accessor, BufPtr, Struct) of
                ok -> ?ESUCCESS;
                {error, efault} -> ?EFAULT
            end
    end.

%% Resolve a standard fd to its fdstat struct binary, or {error, ebadf}.
fdstat_for(_Ctx, 1) ->
    {ok, fdstat_bytes(?FILETYPE_CHARACTER_DEVICE, ?FDFLAGS_NONE, ?RIGHTS_FD_WRITE, ?RIGHTS_NONE)};
fdstat_for(_Ctx, 2) ->
    {ok, fdstat_bytes(?FILETYPE_CHARACTER_DEVICE, ?FDFLAGS_NONE, ?RIGHTS_FD_WRITE, ?RIGHTS_NONE)};
fdstat_for(Ctx, 0) ->
    case wa_wasi_ctx:require_stdin(Ctx) of
        {ok, _Source} ->
            {ok, fdstat_bytes(?FILETYPE_CHARACTER_DEVICE, ?FDFLAGS_NONE, ?RIGHTS_FD_READ, ?RIGHTS_NONE)};
        {error, {missing_capability, _}} ->
            {error, ebadf}
    end;
fdstat_for(_Ctx, _Fd) ->
    {error, ebadf}.

%% Build the 24-byte, 8-byte-aligned `fdstat' struct as one binary:
%%   filetype u8 @0, pad @1, fdflags u16 LE @2, pad @4..7,
%%   fs_rights_base u64 LE @8, fs_rights_inheriting u64 LE @16.
fdstat_bytes(Filetype, Fdflags, RightsBase, RightsInheriting) ->
    Struct =
        <<Filetype:8, 0:8, (encode_u16(Fdflags))/binary, 0:32,
          (encode_u64(RightsBase))/binary, (encode_u64(RightsInheriting))/binary>>,
    ?FDSTAT_SIZE = byte_size(Struct),
    Struct.

%% --------------------------------------------------------------------------
%% fd_read (Req 7)
%%
%% Signature: (Accessor, Ctx, Fd, IovsPtr, IovsLen, NreadPtr) -> Errno. The read
%% counterpart of fd_write: reads from the configured Stdin_Source (fd 0 only)
%% into the iovec buffers in ascending index order until the source is exhausted
%% or every buffer is full, then writes the total bytes read as a u32 at
%% NreadPtr.
%%   Fd /= 0                    -> EBADF, Nread untouched (Req 7.7)
%%   fd 0, no Stdin_Source      -> EBADF, Nread untouched (Req 7.8)
%%   IovsLen == 0               -> write Nread 0, ESUCCESS, no stdin consumed (7.5)
%%   at/after EOF               -> write Nread 0, ESUCCESS (Req 7.6)
%% Atomicity (Req 7.9): the iovec array and every buffer destination plus the
%% Nread slot are bounds-checked (read/probe) BEFORE any Stdin_Source byte is
%% pulled, so an OOB returns EFAULT with memory unmodified and no input consumed.
%% --------------------------------------------------------------------------
-spec fd_read(wa_wasi_memory:accessor(), wa_wasi_ctx:t(),
              integer(), integer(), integer(), integer()) -> integer().
fd_read(_Accessor, _Ctx, Fd, _IovsPtr, _IovsLen, _NreadPtr) when Fd =/= 0 ->
    ?EBADF;
fd_read(Accessor, Ctx, 0, IovsPtr, IovsLen, NreadPtr) ->
    case wa_wasi_ctx:require_stdin(Ctx) of
        {error, {missing_capability, _}} ->
            %% fd 0 with no stdin source: an unreadable descriptor (Req 7.8).
            ?EBADF;
        {ok, Source} ->
            fd_read_1(Accessor, Source, IovsPtr, IovsLen, NreadPtr)
    end.

%% IovsLen == 0: write 0 to Nread, consume no stdin (Req 7.5).
fd_read_1(Accessor, _Source, _IovsPtr, 0, NreadPtr) ->
    case wa_wasi_memory:write(Accessor, NreadPtr, encode_u32(0)) of
        ok -> ?ESUCCESS;
        {error, efault} -> ?EFAULT
    end;
fd_read_1(Accessor, Source, IovsPtr, IovsLen, NreadPtr) ->
    %% (a) read the iovec array (IovsLen * 8 bytes)
    case wa_wasi_memory:read(Accessor, IovsPtr, IovsLen * 8) of
        {error, efault} ->
            ?EFAULT;
        {ok, IovBin} ->
            Iovecs = decode_iovecs(IovBin),
            %% (b) bounds-check every buffer and the Nread slot BEFORE pulling
            %% any stdin bytes, so an OOB consumes no input (Req 7.9).
            case probe_all(Accessor, [{NreadPtr, 4} | Iovecs]) of
                {error, efault} ->
                    ?EFAULT;
                ok ->
                    %% (c) fill buffers in ascending order from the source
                    {Writes, N} = fill_buffers(Iovecs, Source),
                    %% (d) issue the pre-probed writes, then the Nread count
                    ok = write_all(Accessor, Writes),
                    ok = wa_wasi_memory:write(Accessor, NreadPtr, encode_u32(N)),
                    ?ESUCCESS
            end
    end.

%% Probe a list of {Ptr, Len} ranges; ok only if all are in bounds.
probe_all(_Accessor, []) ->
    ok;
probe_all(Accessor, [{Ptr, Len} | Rest]) ->
    case probe(Accessor, Ptr, Len) of
        ok -> probe_all(Accessor, Rest);
        {error, efault} = E -> E
    end.

%% Fill iovec buffers in ascending index order from the Stdin_Source, returning
%% the list of {Ptr, Chunk} writes (only nonempty chunks) and the total byte
%% count. Stops when the source reports EOF (<<>>), or every buffer is full.
fill_buffers(Iovecs, Source) ->
    fill_buffers(Iovecs, Source, [], 0).

fill_buffers([], _Source, Writes, N) ->
    {lists:reverse(Writes), N};
fill_buffers([{_Ptr, 0} | Rest], Source, Writes, N) ->
    %% zero-length buffer: nothing to fill, skip
    fill_buffers(Rest, Source, Writes, N);
fill_buffers([{Ptr, Len} | Rest], Source, Writes, N) ->
    case stdin_pull(Source, Len) of
        {<<>>, _Next} ->
            %% EOF: stop; remaining buffers get nothing (Req 7.6)
            {lists:reverse(Writes), N};
        {Chunk, Next} ->
            Got = byte_size(Chunk),
            Writes1 = [{Ptr, Chunk} | Writes],
            case Got < Len of
                true ->
                    %% source yielded less than this buffer's capacity: treat as
                    %% the source being drained for this call; stop here.
                    {lists:reverse(Writes1), N + Got};
                false ->
                    %% buffer filled exactly; continue with the next buffer
                    fill_buffers(Rest, Next, Writes1, N + Got)
            end
    end.

%% Pull up to Max bytes from a Stdin_Source, returning {Bytes, NextSource}.
%%   {fixed, Bin} — a one-shot source: yield up to Max bytes, the remainder
%%                  becomes the next source; an empty source yields <<>> (EOF).
%%   {fun, F}     — F(Max) -> {Bytes, NextSource}; <<>> signals EOF. A chunk
%%                  longer than Max is truncated so we never overfill a buffer.
stdin_pull({fixed, Bin}, Max) ->
    Take = min(Max, byte_size(Bin)),
    Chunk = binary:part(Bin, 0, Take),
    Rest = binary:part(Bin, Take, byte_size(Bin) - Take),
    {Chunk, {fixed, Rest}};
stdin_pull({'fun', F} = Source, Max) ->
    case F(Max) of
        {Chunk, Next} when is_binary(Chunk) ->
            case byte_size(Chunk) > Max of
                true -> {binary:part(Chunk, 0, Max), Next};
                false -> {Chunk, Next}
            end;
        %% A misbehaving source that returns just bytes keeps the same source
        %% (defensive; the validated shape is {Bytes, Next}).
        Chunk when is_binary(Chunk) ->
            {Chunk, Source}
    end.

%% Issue a list of {Ptr, Bytes} writes; all destinations were pre-probed.
write_all(_Accessor, []) ->
    ok;
write_all(Accessor, [{Ptr, Bytes} | Rest]) ->
    ok = wa_wasi_memory:write(Accessor, Ptr, Bytes),
    write_all(Accessor, Rest).
