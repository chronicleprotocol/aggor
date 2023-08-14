# Deployment

This document describes how to deploy a new `Chainlog` instance via _Chronicle Protocol_'s [`Greenhouse`](https://github.com/chronicleprotocol/greenhouse) contract factory.

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
- `O_CHRON`: The address of the Chronicle Oracle
- `O_CHAIN`: The address of the Chainlink Oracle
- `O_UNI`: [Optional] The address of the Uniswap pool.
    - Note to use zero address (`0x0000000000000000000000000000000000000000`) if Uniswap pool not necessary
- `UNI_BASETOKEN`: If you are using the Uniswap pools `token0` as the base token, set to `1`. If `token1`, set to `0`.

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variables' values, and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "PRIVATE_KEY" -e "ETHERSCAN_API_URL" -e "ETHERSCAN_API_KEY" -e "GREENHOUSE" -e "SALT" -e "INITIAL_AUTHED" -e "O_CHRON" -e "O_CHAIN" -e "O_UNI" -e "UNI_BASETOKEN"
```

## Code Adjustments

Two code adjustments are necessary to give each deployed contract instance a unique name:

1. Adjust the `Aggor_COUNTER`'s name in `src/Aggor.sol` and remove the `@todo` comment
2. Adjust the import of the `Aggor_COUNTER` in `script/Aggor.s.sol` and remove the `@todo` comment

## Execution

The deployment process consists of two steps - the actual deployment and the subsequent Etherscan verification.

Deployment:

```bash
$ SALT_BYTES32=$(cast format-bytes32-string $SALT) && \
  forge script \
    --private-key "$PRIVATE_KEY" \
    --broadcast \
    --rpc-url "$RPC_URL" \
    --sig "$(cast calldata "deploy(address,bytes32,address,address,address,address,bool)" \
        "$GREENHOUSE" "$SALT_BYTES32" "$INITIAL_AUTHED" "$O_CHRON" "$O_CHAIN" "$O_UNI" "$UNI_BASETOKEN")" \
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
        "$(cast abi-encode "constructor(address,address,address,address,bool)" \
            "$INITIAL_AUTHED" "$O_CHRON" "$O_CHAIN" "$O_UNI" "$UNI_BASETOKEN")" \
    src/Aggor.sol:"$SALT"
```
