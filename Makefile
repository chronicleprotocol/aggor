.PHONY: test
test:
	forge test --match-path test/OracleAggregator.t.sol -vvv

.PHONY: test_goerli
test_goerli:
	./test/goerli.sh

.PHONY: deploy
deploy:
	@echo 'To deploy, you need to run something like:'
	@echo 'forge create src/OracleAggregator.sol:OracleAggregator --constructor-args 0x56765C803a52a8fd4B26B3da8FF76D21fF9cB3E4 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e --etherscan-api-key <ETHERSCAN_API_KEY> --verify'
