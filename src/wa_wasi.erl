%% wa_wasi — WASI preview1 host-function library for the Erlang ecosystem.
%%
%% Standalone, pure-Erlang: depends only on OTP and its own `wa_wasi_*'
%% modules — never an `'Elixir.*'' module and never any `wa_embedder*' module
%% (the Independence Invariant). A compiled WASM module imports the
%% `wasi_snapshot_preview1' functions and the host (this library) implements
%% them, parameterized by a `wa_wasi_memory' accessor and a `wa_wasi_ctx'
%% configuration context.
%%
%% This module will expose the public API — `imports/2' (the
%% `wasi_snapshot_preview1' import-map builder) and per-function fun builders.
%% It is scaffolded here and implemented in a later task.
-module(wa_wasi).

%% No exports yet — the public API lands with the import-map builder task.
-export([]).
