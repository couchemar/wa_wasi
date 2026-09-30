# wa_wasi_ex — Elixir wrapper package (mix).
#
# The one thing to remember (and why this Makefile exists): WA_WASI_PATH
# selects the dependency on the Erlang core.
#   * SET   (dev):     {:wa_wasi, path: "..", manager: :rebar3}  -> sibling source
#   * UNSET (publish): {:wa_wasi, "~> 0.1"}                      -> hex release
# `mix hex.build`/`publish` MUST run with WA_WASI_PATH unset (hex refuses a
# path dep), and the core must already be on hex or `mix deps.get` can't resolve
# it. So publish the core first, then this wrapper.
#
# The test suite also pulls `wa_embedder_ex` (only: :test) to compile and run
# real WASM modules end-to-end; it is not part of the shipped package.

# Dev builds resolve the core against the repo root (this dir's parent).
export WA_WASI_PATH ?= ..

.DEFAULT_GOAL := help

.PHONY: help deps refresh compile test format package publish clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

refresh: ## Drop a stale local-core copy (only relevant under WA_WASI_PATH)
	rm -rf deps/wa_wasi _build/*/lib/wa_wasi

deps: ## Fetch deps (dev: sibling core via WA_WASI_PATH)
	mix deps.get

compile: deps ## Compile the wrapper against the sibling core
	mix compile

test: deps ## Run the full test suite
	mix test

format: ## Check Elixir formatting
	mix format --check-formatted

# Packaging/publish must NOT use the dev path dep: unset WA_WASI_PATH so the
# {:wa_wasi, "~> 0.1"} hex dep is used. This requires the core to already be
# published on hex (otherwise deps.get for the wrapper fails). Both targets
# `refresh` first to drop any stale copied path-dep from prior WA_WASI_PATH dev,
# so the tarball resolves against the hex core cleanly.
package: refresh ## Build the hex tarball with the hex core dep (WA_WASI_PATH unset)
	@echo ">> building package with WA_WASI_PATH unset (uses {:wa_wasi, \"~> 0.1\"})"
	env -u WA_WASI_PATH mix deps.get
	env -u WA_WASI_PATH mix hex.build

publish: refresh ## Publish the wrapper to hex; run AFTER the core is published
	@echo ">> publishing wa_wasi_ex. The core wa_wasi must already be on hex."
	env -u WA_WASI_PATH mix deps.get
	env -u WA_WASI_PATH mix hex.publish

clean: ## Remove build artifacts and fetched deps
	rm -rf _build deps
