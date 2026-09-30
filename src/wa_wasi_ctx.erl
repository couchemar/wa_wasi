%% The Config_Context (`wa_wasi_ctx'): the capabilities/configuration value
%% passed to every WASI preview1 host function.
%%
%% It carries exactly six fields — a stdout sink, a stderr sink, a command-line
%% argument list, an environment-variable list, a clock source, and an RNG
%% source. wa_wasi never reads real host resources implicitly: all output,
%% time, and randomness come from the context the caller supplies. Deterministic
%% (`{fixed, ...}') sources make host-function behavior fully testable.
%%
%% Besides the record/constructor/accessors, this module resolves a file
%% descriptor to its configured sink (`sink_for/2') and validates that a
%% required capability is present (`require_sink/2', `require_clock/1',
%% `require_rng/1') — a host function that needs an absent capability fails
%% rather than silently falling back to a real host resource. The opt-in
%% `host_clock/0' / `crypto_rng/0' helpers let a caller *choose* host-backed
%% time/randomness; `new/1' itself never reads a host resource.
%%
%% Pure Erlang: OTP + wa_wasi_* only (no `'Elixir.*'', no `wa_embedder*'').
-module(wa_wasi_ctx).

-export([new/1, stdout/1, stderr/1, args/1, env/1, clock/1, rng/1]).
%% Non-filesystem preview1 completion: stdin source + clock resolution.
-export([stdin/1, clock_res/1]).
%% Capability resolution/validation + opt-in host-backed source helpers.
-export([sink_for/2, require_sink/2, require_clock/1, require_rng/1]).
-export([require_stdin/1, require_clock_res/1]).
-export([host_clock/0, crypto_rng/0]).

-export_type([t/0, sink/0, clock_source/0, rng_source/0, stdin_source/0, clock_res_source/0]).

%% A sink receives fd_write output bytes:
%%   {fun, F}  — call F(Bytes) for each write
%%   collect   — accumulate; readable after the run (handled by the caller/runtime)
%%   {pid, P}  — send {wa_wasi_output, Fd, Bytes} to P
-type sink() :: {'fun', fun((binary()) -> ok)} | collect | {pid, pid()}.

%% A clock source yields a nanosecond timestamp per clock kind:
%%   {fun, F}          — F(realtime | monotonic) -> integer() nanoseconds
%%   {fixed, Rt, Mono} — deterministic realtime/monotonic values
-type clock_source() ::
    {'fun', fun((realtime | monotonic) -> integer())}
    | {fixed, RealtimeNs :: integer(), MonotonicNs :: integer()}.

%% An RNG source yields random bytes:
%%   {fun, F}     — F(N) -> N-byte binary()
%%   {fixed, Bin} — deterministic bytes (cycled/truncated to N)
%%   crypto       — opt-in host randomness (crypto:strong_rand_bytes/1)
-type rng_source() ::
    {'fun', fun((non_neg_integer()) -> binary())}
    | {fixed, binary()}
    | crypto.

%% A Clock_Resolution_Source yields a clock's resolution in nanoseconds per
%% clock kind (mirrors clock_source/0):
%%   {fixed, RtNs, MonoNs} — deterministic per-kind resolutions
%%   {fun, F}              — F(realtime | monotonic) -> non_neg_integer() ns
-type clock_res_source() ::
    {fixed, RealtimeNs :: non_neg_integer(), MonotonicNs :: non_neg_integer()}
    | {'fun', fun((realtime | monotonic) -> non_neg_integer())}.

%% A Stdin_Source yields the bytes readable from fd 0 (mirrors the sink model
%% but is a PULL source with progress):
%%   {fixed, Bytes} — yield Bytes once, then EOF
%%   {fun, F}       — F(Max) -> {Bytes, NextSource}; Bytes = <<>> signals EOF,
%%                    NextSource threads the remaining input for the next pull
-type stdin_source() ::
    {fixed, binary()}
    | {'fun', fun((non_neg_integer()) -> {binary(), stdin_source()})}.

-record(wa_wasi_ctx, {
    stdout :: sink() | undefined,
    stderr :: sink() | undefined,
    args :: [binary()],
    env :: [{binary(), binary()}],
    clock :: clock_source() | undefined,
    rng :: rng_source() | undefined,
    stdin :: stdin_source() | undefined,
    clock_res :: clock_res_source() | undefined
}).

-opaque t() :: #wa_wasi_ctx{}.

%% --------------------------------------------------------------------------
%% Constructor
%% --------------------------------------------------------------------------

%% Build a Config_Context from a plain options map. Recognized keys:
%%   stdout, stderr : a sink() (default undefined — capability absent)
%%   clock          : a clock_source() (default undefined)
%%   rng            : an rng_source() (default undefined)
%%   args           : [binary()] (default [])
%%   env            : [{binary(), binary()}] (default [])
%%   stdin          : a stdin_source() (default undefined — capability absent)
%%   clock_res      : a clock_res_source() (default undefined)
%% Field shapes are validated; a malformed value raises
%% `error({badarg, {wa_wasi_ctx, Field}})'.
-spec new(map()) -> t().
new(Opts) when is_map(Opts) ->
    #wa_wasi_ctx{
        stdout = validate_sink(maps:get(stdout, Opts, undefined)),
        stderr = validate_sink(maps:get(stderr, Opts, undefined)),
        args = validate_args(maps:get(args, Opts, [])),
        env = validate_env(maps:get(env, Opts, [])),
        clock = validate_clock(maps:get(clock, Opts, undefined)),
        rng = validate_rng(maps:get(rng, Opts, undefined)),
        stdin = validate_stdin(maps:get(stdin, Opts, undefined)),
        clock_res = validate_clock_res(maps:get(clock_res, Opts, undefined))
    };
new(_Other) ->
    erlang:error({badarg, {wa_wasi_ctx, opts}}).

%% --------------------------------------------------------------------------
%% Field accessors
%% --------------------------------------------------------------------------

-spec stdout(t()) -> sink() | undefined.
stdout(#wa_wasi_ctx{stdout = V}) -> V.

-spec stderr(t()) -> sink() | undefined.
stderr(#wa_wasi_ctx{stderr = V}) -> V.

-spec args(t()) -> [binary()].
args(#wa_wasi_ctx{args = V}) -> V.

-spec env(t()) -> [{binary(), binary()}].
env(#wa_wasi_ctx{env = V}) -> V.

-spec clock(t()) -> clock_source() | undefined.
clock(#wa_wasi_ctx{clock = V}) -> V.

-spec rng(t()) -> rng_source() | undefined.
rng(#wa_wasi_ctx{rng = V}) -> V.

-spec stdin(t()) -> stdin_source() | undefined.
stdin(#wa_wasi_ctx{stdin = V}) -> V.

-spec clock_res(t()) -> clock_res_source() | undefined.
clock_res(#wa_wasi_ctx{clock_res = V}) -> V.

%% --------------------------------------------------------------------------
%% Capability resolution / validation
%% --------------------------------------------------------------------------

%% Resolve a file descriptor to its configured sink. fd 1 -> stdout, fd 2 ->
%% stderr; any other fd is a bad file descriptor. Note this returns `{error,
%% ebadf}' for an unknown fd (a WASI errno condition, Req 4.8) but does NOT
%% distinguish a valid-but-unconfigured fd — use `require_sink/2' for that.
-spec sink_for(t(), integer()) -> {ok, sink() | undefined} | {error, ebadf}.
sink_for(#wa_wasi_ctx{stdout = S}, 1) -> {ok, S};
sink_for(#wa_wasi_ctx{stderr = S}, 2) -> {ok, S};
sink_for(#wa_wasi_ctx{}, _Fd) -> {error, ebadf}.

%% Require a writable sink for `Fd'. Returns `{ok, Sink}' when fd 1/2 has a
%% configured (non-undefined) sink; `{error, ebadf}' for any fd other than 1/2
%% (Req 4.8); `{error, {missing_capability, {sink, Fd}}}' when the fd is valid
%% but no sink was configured (Req 3.7, 1.5 — no host-resource fallback).
-spec require_sink(t(), integer()) ->
    {ok, sink()} | {error, ebadf} | {error, {missing_capability, {sink, 1 | 2}}}.
require_sink(Ctx, Fd) ->
    case sink_for(Ctx, Fd) of
        {ok, undefined} -> {error, {missing_capability, {sink, Fd}}};
        {ok, Sink} -> {ok, Sink};
        {error, ebadf} = E -> E
    end.

%% Require a configured clock source (Req 3.7, 1.5).
-spec require_clock(t()) ->
    {ok, clock_source()} | {error, {missing_capability, clock}}.
require_clock(#wa_wasi_ctx{clock = undefined}) -> {error, {missing_capability, clock}};
require_clock(#wa_wasi_ctx{clock = C}) -> {ok, C}.

%% Require a configured RNG source (Req 3.7, 1.5).
-spec require_rng(t()) ->
    {ok, rng_source()} | {error, {missing_capability, rng}}.
require_rng(#wa_wasi_ctx{rng = undefined}) -> {error, {missing_capability, rng}};
require_rng(#wa_wasi_ctx{rng = R}) -> {ok, R}.

%% Require a configured Clock_Resolution_Source (Req 2.6). A missing source is a
%% missing_capability error with no host fallback; clock_res_get maps it to a
%% raised exception (like clock_time_get), since WASI has no errno for an
%% unwired clock.
-spec require_clock_res(t()) ->
    {ok, clock_res_source()} | {error, {missing_capability, clock_res}}.
require_clock_res(#wa_wasi_ctx{clock_res = undefined}) ->
    {error, {missing_capability, clock_res}};
require_clock_res(#wa_wasi_ctx{clock_res = C}) ->
    {ok, C}.

%% Require a configured Stdin_Source (Req 3.6). A missing source is a
%% missing_capability error with no host fallback; fd_read / fd_fdstat_get on
%% fd 0 map it to the WASI errno EBADF (an unreadable descriptor).
-spec require_stdin(t()) ->
    {ok, stdin_source()} | {error, {missing_capability, stdin}}.
require_stdin(#wa_wasi_ctx{stdin = undefined}) ->
    {error, {missing_capability, stdin}};
require_stdin(#wa_wasi_ctx{stdin = S}) ->
    {ok, S}.

%% --------------------------------------------------------------------------
%% Opt-in host-backed source helpers
%%
%% These let a caller CHOOSE host-backed time/randomness; `new/1' never wires
%% them implicitly. They read the host only when actually invoked at call time,
%% not at construction.
%% --------------------------------------------------------------------------

%% A clock source backed by the host system clocks (nanoseconds).
-spec host_clock() -> clock_source().
host_clock() ->
    {'fun', fun
        (realtime) -> os:system_time(nanosecond);
        (monotonic) -> erlang:monotonic_time(nanosecond)
    end}.

%% An RNG source backed by `crypto:strong_rand_bytes/1'. Requires the caller's
%% application to have `crypto' started; resolved at call time.
-spec crypto_rng() -> rng_source().
crypto_rng() ->
    crypto.

%% --------------------------------------------------------------------------
%% Field validation (shape only)
%% --------------------------------------------------------------------------

validate_sink(undefined) -> undefined;
validate_sink(collect) -> collect;
validate_sink({'fun', F} = S) when is_function(F, 1) -> S;
validate_sink({pid, P} = S) when is_pid(P) -> S;
validate_sink(_) -> erlang:error({badarg, {wa_wasi_ctx, sink}}).

validate_args(Args) when is_list(Args) ->
    case lists:all(fun is_binary/1, Args) of
        true -> Args;
        false -> erlang:error({badarg, {wa_wasi_ctx, args}})
    end;
validate_args(_) ->
    erlang:error({badarg, {wa_wasi_ctx, args}}).

validate_env(Env) when is_list(Env) ->
    case lists:all(fun is_env_pair/1, Env) of
        true -> Env;
        false -> erlang:error({badarg, {wa_wasi_ctx, env}})
    end;
validate_env(_) ->
    erlang:error({badarg, {wa_wasi_ctx, env}}).

is_env_pair({K, V}) when is_binary(K), is_binary(V) -> true;
is_env_pair(_) -> false.

validate_clock(undefined) -> undefined;
validate_clock({'fun', F} = C) when is_function(F, 1) -> C;
validate_clock({fixed, Rt, Mono} = C) when is_integer(Rt), is_integer(Mono) -> C;
validate_clock(_) -> erlang:error({badarg, {wa_wasi_ctx, clock}}).

validate_rng(undefined) -> undefined;
validate_rng(crypto) -> crypto;
validate_rng({'fun', F} = R) when is_function(F, 1) -> R;
validate_rng({fixed, Bin} = R) when is_binary(Bin) -> R;
validate_rng(_) -> erlang:error({badarg, {wa_wasi_ctx, rng}}).

validate_clock_res(undefined) ->
    undefined;
validate_clock_res({fixed, Rt, Mono} = C) when
    is_integer(Rt), Rt >= 0, is_integer(Mono), Mono >= 0
->
    C;
validate_clock_res({'fun', F} = C) when is_function(F, 1) ->
    C;
validate_clock_res(_) ->
    erlang:error({badarg, {wa_wasi_ctx, clock_res}}).

validate_stdin(undefined) ->
    undefined;
validate_stdin({fixed, Bin} = S) when is_binary(Bin) ->
    S;
validate_stdin({'fun', F} = S) when is_function(F, 1) ->
    S;
validate_stdin(_) ->
    erlang:error({badarg, {wa_wasi_ctx, stdin}}).
