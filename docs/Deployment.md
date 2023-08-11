# Deployment

This document describes how to deploy a new `Chainlog` instance via _Chronicle Protocol_'s [`Greenhouse`](https://github.com/chronicleprotocol/greenhouse) contract factory.

## Environment Variables

The following environment variables must be set:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `GREENHOUSE`: The `Greenhouse` instance to use for deployment
- `SALT`: The salt to deploy the `Aggor` instance to
    - Note to use the salt's string representation
    - Note that the salt must not exceed 32 bytes in length
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Aggor` instance
- `O_CHRON`: The address of the Chronicle Oracle
- `O_CHAIN`: The address of the Chainlink Oracle
- `O_UNI`: [Optional] The address of the Uniswap pool. If not going to use, set to the zero address `0x0000000000000000000000000000000000000000`
- `UNI_BASETOKEN`: If you are using the Uniswap pools `token0` as the base token (generally the case), set to `1`. If `token1`, set to `0`.

## Code Adjustments

You need to make some source code edits before running the deploy. Note that these edits should NOT be checked in, they are only temporary and can be discarded. The record of the deploy must be added to the `chronicles` repo.

### Script file

Adjust the name of the `Aggor` instance to deploy inside `script/Aggor.s.sol`.

1. Adjust the name of the `Aggor_COUNTER` contract
2. Adjust the name of the contract inside the `deploy` function
3. Remove both `@todo` comments

### Contract source 

Adjust the name of the `Aggor` contract to match the name replacing `Aggor_COUNTER` in `script/Aggor.s.sol`.

This is exclusively for the verification step below.

## Execution

You need to run the deploy and the verification separately. First do the deploy:

```bash
SALT_BYTES32=$(cast --format-bytes32-string $SALT) && \
forge script \
	--private-key "$PRIVATE_KEY" \
	--broadcast \
	--rpc-url "$RPC_URL" \
    --sig "$(cast calldata "deploy(address,bytes32,address,address,address,address,bool)" \
        "$GREENHOUSE" "$SALT_BYTES32" "$AUTHED_DEPLOYER" "$O_CHRON" "$O_CHAIN" "$O_UNI" "$UNI_BASETOKEN")" \
   script/Aggor.s.sol:AggorScript

```

If the deploy was successful, the next step is to verify. You should now have a `$DEPLOY_ADDRESS` which you can provide to the following command.

```bash
forge verify-contract \
    "$DEPLOY_ADDRESS" \
    --verifier-url "$ETHERSCAN_API_URL" \
    --etherscan-api-key "$ETHERSCAN_KEY" \
    src/Aggor.sol:"$SALT" \
    --constructor-args \
        "$(cast abi-encode "constructor(address,address,address,address,bool)" \
            "$AUTHED_DEPLOYER" "$O_CHRON" "$O_CHAIN" "$O_UNI" "$unibase_token")" \
    --watch
```

Note that `$ETHERSCAN_API_URL` above needs to point to the correct Etherscan API for the given chain and environent. E.g. for Optimism, you would pick one of these:

[https://docs.optimism.etherscan.io/v/optimistic-goerli-etherscan](https://docs.optimism.etherscan.io/v/optimistic-goerli-etherscan)


