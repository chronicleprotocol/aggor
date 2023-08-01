# Aggor Script

This document describes how to deploy and manage `Aggor` instances via the `Aggor.s.sol`'s `AggorScript`.

The following environment variables are necessary for all commands:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use

Note that foundry offers different wallet options, for more info see `$ forge script -h`.

## Deployment

Set the following environment variables:
- `ETHERSCAN_API_KEY`: The Etherscan API key for the Etherscan's chain instance
- `GREENHOUSE`: The `Greenhouse` instance to use for deployment
- `SALT`: The salt to deploy the `Aggor` instance to
    - Note to use the salt's string representation
    - Note that the salt must not exceed 32 bytes in length
- `INITIAL_AUTHED`: The address being auth'ed on the newly deployed `Aggor` instance
- `CHRONICLE`: The Chronicle oracle to use
- `CHAINLINK`: The Chainlink oracle to use
- `UNI_POOL`: The Uniswap pool of which's TWAP to use
    - Note that providing a Uniswap pool is optional
    - If no Uniswap pool necessary, use zero address (`0x0000000000000000000000000000000000000000`)
- `UNI_USE_TOKEN_0_AS_BASE`: Whether Uniswap's token0 is the base asset
    - Note that value must either `true` or `false`

Adjust the following lines in `script/Aggor.s.sol` and remove the corresponding `@todo`'s:
- `contract Aggor_X is Aggor`
    - Adjust the `Aggor_X` name
- `type(Aggor_X).creationCode`
    - Adjust the `Aggor_X` name

Run:
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

## Management

The following environment variables are necessary for all management commands:
- `AGGOR`: The `Aggor` instance's address

### `IAggor::poke`

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "poke(address)" $AGGOR) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAggor::setStalenessThreshold`

Set the following environment variables:
- `STALENESS_THRESHOLD`: The staleness threshold to set

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setStalenessThreshold(address,uint32)" $AGGOR $STALENESS_THRESHOLD) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAggor::setSpread`

Set the following environment variables:
- `SPREAD`: The spread to set

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setSpread(address,uint16)" $AGGOR $SPREAD) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAggor::useUniswap`

Set the following environment variables:
- `USE_UNISWAP`: Whether to use Uniswap's TWAP or not
    - Note that value must either `true` or `false`

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "useUniswap(address,bool)" $AGGOR $USE_UNISWAP) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAggor::setUniSecondsAgo`

Set the following environment variables:
- `UNI_SECONDS_AGO`: Lookback time in seconds for Uniswap's TWAP oracle

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setUniSecondsAgo(address,uint32)" $AGGOR $UNI_SECONDS_AGO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAuth::rely`

Set the following environment variables:
- `WHO`: The address to grant auth to

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "rely(address,address)" $AGGOR $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAuth::deny`

Set the following environment variables:
- `WHO`: The address renounce auth from

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "deny(address,address)" $AGGOR $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IToll::kiss`

Set the following environment variables:
- `WHO`: The address grant toll to

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "kiss(address,address)" $AGGOR $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IToll::diss`

Set the following environment variables:
- `WHO`: The address renounce toll from

Run:
```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "diss(address,address)" $AGGOR $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```
