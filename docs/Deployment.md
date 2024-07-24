# Deployment

This document describes how to deploy a new `Aggor` instance.

## Environment Variables

The following environment variables must be set:

- `RPC_URL`: The RPC URL of an EVM node
- `KEYSTORE`: The path to the keystore file containing the encrypted private key
    - Note that password can either be entered on request or set via the `KEYSTORE_PASSWORD` environment variable
- `KEYSTORE_PASSWORD`: The password for the keystore file
- `ETHERSCAN_API_URL`: The Etherscan API URL for the Etherscan's chain instance
    - Note that the API endpoint varies per Etherscan chain instance
    - Note to point to actual API endpoint (e.g. `/api`) and not just host
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Aggor` instance

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variables' values, and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "KEYSTORE" -e "KEYSTORE_PASSWORD" -e "ETHERSCAN_API_URL" -e "ETHERSCAN_API_KEY" -e "INITIAL_AUTHED"
```

## Configuration Setting

The following additional environment variables must be set:

- `BUD`: The address allowed to read Aggor
- `CHRONICLE`: The Chronicle oracle
- `CHAINLINK`: The Chainlink oracle
- `UNISWAP_POOL`: The Uniswap pool to use as TWAP
- `UNISWAP_BASE_TOKEN`: The Uniswap pool's base token
- `UNISWAP_QUOTE_TOKEN`: The Uniswap pool's quote token
- `UNISWAP_BASE_TOKEN_DECIMALS`: The Uniswap pool's base token's decimals
- `UNISWAP_LOOKBACK`: The TWAP lookback argument in seconds
- `AGREEMENT_DISTANCE`: The agreement distance in WAD
- `AGE_THRESHOLD`: The age staleness threshold in seconds

## Code Adjustments

Two code adjustments are necessary to give each deployed contract instance a unique name:

1. Adjust the `Aggor_BASE_QUOTE_COUNTER`'s name in `src/Aggor.sol` and remove the `@todo` comment
2. Adjust the import of the `Aggor_BASE_QUOTE_COUNTER` in `script/Aggor.s.sol` and remove the `@todo` comment

## Execution

The deployment process consists of two steps - the actual deployment and the subsequent Etherscan verification.

Deployment:

```bash
$ forge script \
    --keystore "$KEYSTORE" \
    --password "$KEYSTORE_PASSWORD" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig "$(cast calldata "deploy(address,address,address,address,address,address,address,uint8,uint32,uint128,uint32)" "$INITIAL_AUTHED" "$BUD" "$CHRONICLE" "$CHAINLINK" "$UNISWAP_POOL" "$UNISWAP_BASE_TOKEN" "$UNISWAP_QUOTE_TOKEN" "$UNISWAP_BASE_TOKEN_DECIMALS" "$UNISWAP_LOOKBACK" "$AGREEMENT_DISTANCE" "$AGE_THRESHOLD")" \
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
        "$(cast abi-encode "constructor(address,address,address,address,address,address,address,uint8,uint32,uint128,uint32)" \
        "$INITIAL_AUTHED" "$BUD" "$CHRONICLE" "$CHAINLINK" "$UNISWAP_POOL" "$UNISWAP_BASE_TOKEN" "$UNISWAP_QUOTE_TOKEN" "$UNISWAP_BASE_TOKEN_DECIMALS" "$UNISWAP_LOOKBACK" "$AGREEMENT_DISTANCE" "$AGE_THRESHOLD")" \
    src/Aggor.sol:"$SALT"
```
