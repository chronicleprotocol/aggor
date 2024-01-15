# Management

This document describes how to manage deployed `Aggor` instances.

## Table of Contents

- [Management](#management)
  - [Table of Contents](#table-of-contents)
  - [Environment Variables](#environment-variables)
  - [Functions](#functions)
    - [`IAggor::setAgreementDistance`](#iaggorsetagreementdistance)
    - [`IAggor::setAgeThreshold`](#iaggorsetagethreshold)
    - [`IAuth::rely`](#iauthrely)
    - [`IAuth::deny`](#iauthdeny)
    - [`IToll::kiss`](#itollkiss)
    - [`IToll::diss`](#itolldiss)

## Environment Variables

The following environment variables must be set for all commands:

- `RPC_URL`: The RPC URL of an EVM node
- `PRIVATE_KEY`: The private key to use
- `AGGOR`: The `Aggor` instance to manage

Note that an `.env.example` file is provided in the project root. To set all environment variables at once, create a copy of the file and rename the copy to `.env`, adjust the variables' values, and run `source .env`.

To easily check the environment variables, run:

```bash
$ env | grep -e "RPC_URL" -e "PRIVATE_KEY" -e "AGGOR"
```

## Functions

## `IAggor::setAgreementDistance`

Set the following environment variables:

- `AGREEMENT_DISTANCE`: The agreement distance in BPS to set

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setAgreementDistance(address,uint16)" "$AGGOR" "$AGREEMENT_DISTANCE") \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IAggor::setAgeThreshold`

Set the following environment variables:

- `AGE_THRESHOLD`: The age threshold to set

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "setAgeThreshold(address,uint32)" "$AGGOR" "$AGE_THRESHOLD") \
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

- `WHO`: The address to renounce auth from

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "deny(address,address)" $CHAINLOG $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IToll::kiss`

Set the following environment variables:

- `WHO`: The address to grant toll to

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "kiss(address,address)" $SCRIBE $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```

### `IToll::diss`

Set the following environment variables:

- `WHO`: The address to renounce toll from

Run:

```bash
$ forge script \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --rpc-url $RPC_URL \
    --sig $(cast calldata "diss(address,address)" $SCRIBE $WHO) \
    -vvv \
    script/Aggor.s.sol:AggorScript
```
