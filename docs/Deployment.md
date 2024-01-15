# Deployment

This document describes how to deploy a new `Aggor` instance via _Chronicle Protocol_'s [`Greenhouse`](https://github.com/chronicleprotocol/greenhouse) contract factory.

## Environment Variables

The following environment variables must be set:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use
- `ETHERSCAN_API_URL`: The Etherscan API URL for the Etherscan's chain instance
    - Note that the API endpoint varies per Etherscan chain instance
    - Note to point to actual API endpoint (e.g. `/api`) and not just host
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `GREENHOUSE`: The `Greenhouse` instance to use for deployment
- `SALT`: The salt to deploy the `Aggor` instance to
    - Note to use the salt's string representation
    - Note that the salt must not exceed 32 bytes in length
    - Note that the salt should match the name of the contract deployed!
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Aggor` instance
- `IS_PEGGED_ASSET`: Whether `Aggor` instance should be in pegged asset mode
- `PEGGED_PRICE`: The pegged price to use as heuristic. Must be zero if not in pegged mode, otherwise non-zero
- `CHRONICLE`: The address of the Chronicle Oracle
- `CHAINLINK`: The address of the Chainlink Oracle
- `UNISWAP_POOL`: The address of the Uniswap pool to use as twap
- `UNISWAP_BASE_TOKEN`: The base asset token address
- `UNISWAP_QUOTE_TOKEN`: The quote asset token address
- `UNISWAP_BASE_TOKEN_DECIMALS`: The base asset token's decimals
- `UNISWAP_LOOKBACK`: The number of seconds to use as lookback for the Uniswap TWAP oracle
- `AGREEMENT_DISTANCE`: Agreement distance in BPS
- `AGE_THRESHOLD`: The max acceptable age of an oracle answer in seconds

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variables' values, and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "PRIVATE_KEY" -e "ETHERSCAN_API_URL" -e "ETHERSCAN_API_KEY" -e "GREENHOUSE" -e "SALT" -e "INITIAL_AUTHED" -e "IS_PEGGED_ASSET" -e "PEGGED_PRICE" -e "CHRONICLE" -e "CHAINLINK" -e "UNISWAP_POOL" -e "UNISWAP_BASE_TOKEN" -e "UNISWAP_QUOTE_TOKEN" -e "UNISWAP_BASE_TOKEN_DECIMALS" -e "UNISWAP_LOOKBACK" -e "AGREEMENT_DISTANCE" -e "AGE_THRESHOLD"
```

## Code Adjustments

Two code adjustments are necessary to give each deployed contract instance a unique name:

1. Adjust the `Aggor_BASE_QUOTE_COUNTER`'s name in `src/Aggor.sol` and remove the `@todo` comment
2. Adjust the import of the `Aggor_BASE_QUOTE_COUNTER` in `script/Aggor.s.sol` and remove the `@todo` comment

## Execution

The deployment process consists of two steps - the actual deployment and the subsequent Etherscan verification.

Deployment:

```bash
$ SALT_BYTES32=$(cast format-bytes32-string $SALT) && \
  forge script \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig "$(cast calldata "deploy(address,bytes32,address,bool,uint128,address,address,address,address,address,uint8,uint32,uint16,uint32)" \
        "$GREENHOUSE" "$SALT_BYTES32" "$INITIAL_AUTHED" "$IS_PEGGED_ASSET" "$PEGGED_PRICE" "$CHRONICLE" "$CHAINLINK" "$UNISWAP_POOL" "$UNISWAP_BASE_TOKEN" "$UNISWAP_QUOTE_TOKEN" "$UNISWAP_BASE_TOKEN_DECIMALS" "$UNISWAP_LOOKBACK" "$AGREEMENT_DISTANCE" "$AGE_THRESHOLD")" \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

The deployment command will log the address of the newly deployed contract address. Store this address in the `$AGGOR` environment variable and continue with the verification.

Verification:

```bash
$ forge verify-contract \
    "$AGGOR" \
    --verifier-url "$ETHERSCAN_API_URL" \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --watch \
    --constructor-args \
        "$(cast abi-encode "constructor(address,bool,uint128,address,address,address,address,address,uint8,uint32,uint16,uint32)" \
        "$INITIAL_AUTHED" "$IS_PEGGED_ASSET" "$PEGGED_PRICE" "$CHRONICLE" "$CHAINLINK" "$UNISWAP_POOL" "$UNISWAP_BASE_TOKEN" "$UNISWAP_QUOTE_TOKEN" "$UNISWAP_BASE_TOKEN_DECIMALS" "$UNISWAP_LOOKBACK" "$AGREEMENT_DISTANCE" "$AGE_THRESHOLD")" \
    src/Aggor.sol:"$SALT"
```
