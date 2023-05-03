![](./assets/title.png)

Aggregate Oracle that combines the prices of multiple sources into a mean value. Resiliency and distributed trust.

# Overview

The `AggregateOracle` contract has two basic functions:

## poke()

The `poke()` function pulls the price from the price _sources_ and if there is no error getting the price, generates and stores the average of those prices as `lastAgreedMeanPrice`. If there ever is an error retrieving a price from a source, `lastAgreedMeanPrice` will not be updated. In this way we ensure that (1) we always provide a price, and (2) in the event of an error we do not update the price with a bad price.

## valueRead()

The primary way to access the value produced by `poke()` is 

```
  function valueRead() external view returns (uint256, bool);
```

It returns the price `uint256` and a bool flagging whether the price is stale or not. The "staleness threshold" can be configured via `setStalenessThreshold()`.

## Compatibility

Because this contract provides the price of more than one oracle source (currently Chronicle and Chainlink), we provide compatibility functions for consumers of one or the other source. This way no code modifications are required for any customer who wants to switch to the aggregate oracle.

### Maker/Chronicle

If the consumer is using the Maker style median oracle, they can use 

```
function read() external view returns (uint256);
```

If the consumer is using Chainlink oracles, the following compatibility functions are available:

```
function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
function latestAnswer() external view returns (int256); // deprecated
```

Note that in all cases, we are returning `lastAgreedMeanPrice` for price.

# Gas report

The `poke()` function is quite expensive:

```
Test result: ok. 3 passed; 0 failed; finished in 1.05ms
| src/OracleAggregator.sol:OracleAggregator contract |                 |       |        |        |         |
|----------------------------------------------------|-----------------|-------|--------|--------|---------|
| Deployment Cost                                    | Deployment Size |       |        |        |         |
| 553384                                             | 2781            |       |        |        |         |
| Function Name                                      | min             | avg   | median | max    | # calls |
| latestAnswer                                       | 349             | 349   | 349    | 349    | 1       |
| latestRoundData                                    | 891             | 891   | 891    | 891    | 1       |
| poke                                               | 3580            | 96100 | 162807 | 167007 | 7       |
| read                                               | 304             | 304   | 304    | 304    | 1       |
| setStalenessThreshold                              | 22607           | 22607 | 22607  | 22607  | 3       |
| stalenessThresholdSec                              | 317             | 1117  | 317    | 2317   | 5       |
| valueRead                                          | 678             | 1178  | 678    | 4678   | 8       |
```

However, the idea is that as the customer base grows, the cost of `poke()` becomes distributed.