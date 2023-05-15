.PHONY: test
test:
	forge test -vvv
	forge fmt --check

.PHONY: gas_report
gas_report:
	@echo "Gas report taken $$(date -u)"
	forge t --gas-report --match-test poke_basic

.PHONY: snapshot
snapshot:
	forge snapshot --nmt "Fuzz"
