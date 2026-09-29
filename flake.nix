{
  description = "WASI preview1 host functions for the Erlang ecosystem";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            cmake
            elixir
            erlang
            ninja
            rebar3
            wabt
          ];
          ERL_INCLUDE_PATH = "${pkgs.erlang}/lib/erlang/usr/include";

          # Wrapper -> core (mix path dep): wa_wasi_ex/mix.exs reads WA_WASI_PATH
          # to build against the sibling Erlang core (the repo root). Interpreted
          # relative to the wa_wasi_ex project dir, so ".." points at this repo
          # root.
          WA_WASI_PATH = "..";
        };
      }
    );
}
