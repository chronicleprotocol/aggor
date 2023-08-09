# Deployment

This document describes how to deploy a new `Aggor` instance via _Chronicle Protocol_'s [`Greenhouse`](https://github.com/chronicleprotocol/greenhouse) contract factory.

## Environment Variables

The following environment variables must be set:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `GREENHOUSE`: The `Greenhouse` instance to use for deployment
- `SALT`: The salt to deploy the `Scribe` instance to
    - Note to use the salt's string representation
    - Note that the salt must not exceed 32 bytes in length
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Scribe` instance
- `CHRONICLE`: The Chronicle oracle to use
- `CHAINLINK`: The Chainlink oracle to use
- `UNI_POOL`: The Uniswap pool of which's TWAP to use
    - Note that providing a Uniswap pool is optional
    - If no Uniswap pool necessary, use zero address (`0x0000000000000000000000000000000000000000`)
- `UNI_USE_TOKEN_0_AS_BASE`: Whether Uniswap's token0 is the base asset
    - Note that value must either `true` or `false`

## Code Adjustments

Adjust the name of the `Aggor` instance to deploy inside `script/Aggor.s.sol`.

1. Adjust the name of the `Aggor_COUNTER` contract
2. Adjust the name of the contract inside the `deploy` function
3. Remove both `@todo` comments

## Execution

```bash
$ SALT_BYTES32=$(cast --format-bytes32-string $SALT) && \
  forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verify \
    --sig $(cast calldata "deploy(address,bytes32,address,address,address,address,bool) $GREENHOUSE $SALT_BYTES32 $INITIAL_AUTHED $CHRONICLE $CHAINLINK $UNI_POOL $UNI_USE_TOKEN_0_AS_BASE) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```
