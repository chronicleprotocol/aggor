.PHONY: test
test:
	forge test --match-path test/OracleAggregator.t.sol -vvv

.PHONY: test_goerli
test_goerli:
	./test/goerli.sh
