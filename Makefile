.PHONY: test
test: ## Run tests and format code
	forge test -vvv
	forge fmt --check

.PHONY: gas_report
gas_report: ## Print gas report
	@echo "Gas report taken $$(date -u)"
	forge t --gas-report --match-test poke_basic

.PHONY: snapshot
snapshot: ## Update forge's snapshot file
	forge snapshot --nmt "Fuzz|Integration"

.PHONY: help
help: ## Help command
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
