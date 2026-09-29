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

%% Pure codec helpers (the rest of the API — the host functions — is added in
%% later tasks).
-export([encode_u32/1, decode_u32/1, encode_u64/1, decode_iovecs/1]).

%% Errno constants exported as 0-arity functions so callers/tests can name them
%% without duplicating the literals. The macros below are used internally.
-export([esuccess/0, ebadf/0, einval/0, efault/0]).

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
