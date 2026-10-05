%% wa_wasi — WASI preview1 host-function library for the Erlang ecosystem.
%%
%% Public API. `imports/2' builds the `wasi_snapshot_preview1' import map — one
%% closure per host function, each of the EXACT WASM arity and closing over a
%% Memory_Accessor (`wa_wasi_memory') and a Config_Context (`wa_wasi_ctx'). The
%% map merges straight into a WASM runtime's import map (e.g. wa_embedder's),
%% where each local fun is dispatched as a closure.
%%
%% The arity of each closure must match the imported WASM function type's
%% parameter count exactly:
%%   fd_write/4, args_sizes_get/2, args_get/2, environ_sizes_get/2,
%%   environ_get/2, clock_time_get/3, random_get/2, proc_exit/1.
%%
%% Per-function fun builders (`fd_write_fun/2' etc.) are exposed so a caller can
%% wire a single import without the full map.
%%
%% Standalone, pure Erlang: OTP + wa_wasi_* only (no `'Elixir.*'', no
%% `wa_embedder*'').
-module(wa_wasi).

-export([imports/2]).
-export([
    fd_write_fun/2,
    args_sizes_get_fun/2,
    args_get_fun/2,
    environ_sizes_get_fun/2,
    environ_get_fun/2,
    clock_time_get_fun/2,
    random_get_fun/2,
    proc_exit_fun/2,
    clock_res_get_fun/2,
    sched_yield_fun/2,
    fd_fdstat_get_fun/2,
    fd_read_fun/2,
    fd_close_fun/2,
    fd_seek_fun/2
]).

%% The WASM import module name WASI preview1 functions are published under.
-define(MODULE_NAME, <<"wasi_snapshot_preview1">>).

%% Build the `wasi_snapshot_preview1' import map for a given memory accessor and
%% configuration context. Returns `#{ModuleName => #{FnName => Fun}}' where each
%% Fun has the exact WASM arity and closes over `Accessor'/`Ctx'.
-spec imports(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    #{binary() => #{binary() => fun()}}.
imports(Accessor, Ctx) ->
    #{
        ?MODULE_NAME => #{
            <<"fd_write">> => fd_write_fun(Accessor, Ctx),
            <<"args_sizes_get">> => args_sizes_get_fun(Accessor, Ctx),
            <<"args_get">> => args_get_fun(Accessor, Ctx),
            <<"environ_sizes_get">> => environ_sizes_get_fun(Accessor, Ctx),
            <<"environ_get">> => environ_get_fun(Accessor, Ctx),
            <<"clock_time_get">> => clock_time_get_fun(Accessor, Ctx),
            <<"random_get">> => random_get_fun(Accessor, Ctx),
            <<"proc_exit">> => proc_exit_fun(Accessor, Ctx),
            <<"clock_res_get">> => clock_res_get_fun(Accessor, Ctx),
            <<"sched_yield">> => sched_yield_fun(Accessor, Ctx),
            <<"fd_fdstat_get">> => fd_fdstat_get_fun(Accessor, Ctx),
            <<"fd_read">> => fd_read_fun(Accessor, Ctx),
            <<"fd_close">> => fd_close_fun(Accessor, Ctx),
            <<"fd_seek">> => fd_seek_fun(Accessor, Ctx)
        }
    }.

%% --------------------------------------------------------------------------
%% Per-function arity-exact fun builders. Each captures Accessor + Ctx and
%% exposes the WASM-visible arity.
%% --------------------------------------------------------------------------

-spec fd_write_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer(), integer(), integer()) -> integer()).
fd_write_fun(Accessor, Ctx) ->
    fun(Fd, IovsPtr, IovsLen, NwrittenPtr) ->
        wa_wasi_preview1:fd_write(Accessor, Ctx, Fd, IovsPtr, IovsLen, NwrittenPtr)
    end.

-spec args_sizes_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
args_sizes_get_fun(Accessor, Ctx) ->
    fun(CountPtr, BufSizePtr) ->
        wa_wasi_preview1:args_sizes_get(Accessor, Ctx, CountPtr, BufSizePtr)
    end.

-spec args_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
args_get_fun(Accessor, Ctx) ->
    fun(PtrArrayPtr, BufPtr) ->
        wa_wasi_preview1:args_get(Accessor, Ctx, PtrArrayPtr, BufPtr)
    end.

-spec environ_sizes_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
environ_sizes_get_fun(Accessor, Ctx) ->
    fun(CountPtr, BufSizePtr) ->
        wa_wasi_preview1:environ_sizes_get(Accessor, Ctx, CountPtr, BufSizePtr)
    end.

-spec environ_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
environ_get_fun(Accessor, Ctx) ->
    fun(PtrArrayPtr, BufPtr) ->
        wa_wasi_preview1:environ_get(Accessor, Ctx, PtrArrayPtr, BufPtr)
    end.

-spec clock_time_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer(), integer()) -> integer()).
clock_time_get_fun(Accessor, Ctx) ->
    fun(ClockId, Precision, TimePtr) ->
        wa_wasi_preview1:clock_time_get(Accessor, Ctx, ClockId, Precision, TimePtr)
    end.

-spec random_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
random_get_fun(Accessor, Ctx) ->
    fun(BufPtr, BufLen) ->
        wa_wasi_preview1:random_get(Accessor, Ctx, BufPtr, BufLen)
    end.

%% proc_exit ignores the accessor (it touches no memory); the builder keeps the
%% uniform (Accessor, Ctx) shape for a consistent call site.
-spec proc_exit_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer()) -> no_return()).
proc_exit_fun(_Accessor, Ctx) ->
    fun(Code) ->
        wa_wasi_preview1:proc_exit(Ctx, Code)
    end.

%% clock_res_get captures Accessor + Ctx and exposes WASM arity 2.
-spec clock_res_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
clock_res_get_fun(Accessor, Ctx) ->
    fun(ClockId, ResPtr) ->
        wa_wasi_preview1:clock_res_get(Accessor, Ctx, ClockId, ResPtr)
    end.

%% sched_yield ignores the accessor (it touches no memory); the builder keeps the
%% uniform (Accessor, Ctx) shape for a consistent call site.
-spec sched_yield_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun(() -> integer()).
sched_yield_fun(_Accessor, Ctx) ->
    fun() ->
        wa_wasi_preview1:sched_yield(Ctx)
    end.

%% fd_fdstat_get captures Accessor + Ctx and exposes WASM arity 2.
-spec fd_fdstat_get_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer()) -> integer()).
fd_fdstat_get_fun(Accessor, Ctx) ->
    fun(Fd, BufPtr) ->
        wa_wasi_preview1:fd_fdstat_get(Accessor, Ctx, Fd, BufPtr)
    end.

%% fd_read captures Accessor + Ctx and exposes WASM arity 4.
-spec fd_read_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer(), integer(), integer()) -> integer()).
fd_read_fun(Accessor, Ctx) ->
    fun(Fd, IovsPtr, IovsLen, NreadPtr) ->
        wa_wasi_preview1:fd_read(Accessor, Ctx, Fd, IovsPtr, IovsLen, NreadPtr)
    end.
% fd_close takes 1 WASM param (Fd) and returns errno.
-spec fd_close_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer()) -> integer()).
fd_close_fun(Accessor, Ctx) ->
    fun(Fd) -> wa_wasi_preview1:fd_close(Accessor, Ctx, Fd) end.

% fd_seek takes 4 WASM params (Fd, Offset, Whence, NewOffsetPtr) and returns errno.
-spec fd_seek_fun(wa_wasi_memory:accessor(), wa_wasi_ctx:t()) ->
    fun((integer(), integer(), integer(), integer()) -> integer()).
fd_seek_fun(Accessor, Ctx) ->
    fun(Fd, Offset, Whence, NewOffsetPtr) ->
        wa_wasi_preview1:fd_seek(Accessor, Ctx, Fd, Offset, Whence, NewOffsetPtr)
    end.
