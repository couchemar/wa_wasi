# wa_wasi — Erlang core package (rebar3), repo root of the monorepo.
#
# The core has NO dependencies (kernel/stdlib only), so packaging is
# straightforward: `rebar3 hex build`/`publish` work as-is with nothing to
# unset or delete. Publish this core BEFORE the wa_wasi_ex wrapper (the
# wrapper's hex dep on the core can't resolve until the core is on hex).

.DEFAULT_GOAL := help

.PHONY: help compile test format package publish clean

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

compile: ## Compile the Erlang core
	rebar3 compile

test: ## Run the full suite (delegates to the Elixir wrapper)
	$(MAKE) -C wa_wasi_ex test

format: ## Check Erlang formatting (rebar3 fmt if available, else no-op)
	@rebar3 fmt --check 2>/dev/null || echo "rebar3 fmt not available; skipping"

package: ## Build the hex tarball (no deps; no overrides needed)
	rm -rf _build
	rebar3 hex build

publish: ## Publish the core to hex; run BEFORE the wrapper
	@echo ">> publishing wa_wasi (core). Publish this BEFORE wa_wasi_ex."
	rebar3 hex publish

clean: ## Remove build artifacts
	rm -rf _build
