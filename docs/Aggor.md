# Aggor

This document provides technical documentation for Chronicle Protocol's Aggor oracle system.

## Table of Contents

- [Aggor](#aggor)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [`poke()` Function](#poke-function)
  - [Chainlink Compatibility](#chainlink-compatibility)
  - [Benchmarks](#benchmarks)

## Overview

Aggor is an oracle distributing trust among different oracle providers via reading from multiple oracle sources.
The oracle providers supported are _Chronicle Protocol_, _Chainlink_, and _Uniswap TWAP_.

Aggor always uses an _Chronicle Protocol_ oracle, however, the second oracle can be switched from _Chainlink_ to _Uniswap TWAP_ and vice versa.

Aggor's value is the mean of the two oracle's value iff the difference of their values is within a configured spread. If the oracle's values differ more than the spread, the oracle's value having less difference to Aggor's current value is chosen.

## `poke()` Function

The `poke()` function pulls the values from the oracle sources and, if there is no error getting the values, advances its own value to either the mean of the values or the oracle's value with less difference to Aggor's current value.

If an error occurs during reading the oracle sources, Aggor's value will __not__ be updated but the call reverts instead.

## Chainlink Compatibility

Aggor aims to be partially Chainlink compatible by implementing the most widely used functions of the `IChainlinkAggregatorV3` interface.

The following `IChainlinkAggregatorV3` functions are provided:
- `latestRoundData()`
- `latestAnswer()`
- `decimals()`

## Low liquidity Uniswap pools

If a low liquidity pool is used in Aggor, the cost of price manipulation of the internal uniswap oracle is drastically reduced. However, because of the technicalities required, an attacker will at least need to control two consecutive blocks (potentially more) to make their manipulation succesful, which mitigates the risk. High liquidity pools will always be sought first as well, and deployments will only be done after a thorough risk analysis.

## Price jump

The spread limit guards against single outliers in one of the price feeds, making the aggregate price generally less volatile than the sources. However, if the values of the two feeds diverge slowly, the price will experience a sudden jump of approximately `spread/2` when the difference is greater than `spread`.

## Price manipulation

There is an inherent trust assumption in Aggor that the oracle *sources* are difficult to manipulate, that is, designed in and of themselves to be manipulation resistant, especially for a significant amount of time.

Aggor’s `spread` minimizes this risk further by preventing large deviations in a single update. Effectively, customers do not need to trust a given oracle system at any point in time. However, over some period of time trust in both oracles is required.

For example, if one oracle ceases to update, but the other does not, Aggor price will (in time) "go stale" and give the price that was last agreed upon when both oracle systems were reporting. This timeframe should allow enough time for an operational reaction. Good monitoring and contingencies will be necessary, and in place to further guard against price manipulation.

## Benchmarks

A gas report for the `poke()` function can be created via `make gas_report`.

```
Gas report taken Thu Jul 20 18:23:19 UTC 2023
forge t --gas-report --match-test poke_basic
[⠒] Compiling...
No files changed, compilation skipped

Running 1 test for test/Runner.t.sol:AggorTest
[PASS] testFuzz_poke_basic(uint128,uint128,uint256,uint256,uint256) (runs: 256, μ: 165830, ~: 165956)
Test result: ok. 1 passed; 0 failed; finished in 46.77ms
| src/Aggor.sol:Aggor contract |                 |       |        |       |         |
|------------------------------|-----------------|-------|--------|-------|---------|
| Deployment Cost              | Deployment Size |       |        |       |         |
| 2200182                      | 12072           |       |        |       |         |
| Function Name                | min             | avg   | median | max   | # calls |
| chainlink                    | 700             | 700   | 700    | 700   | 1       |
| chronicle                    | 744             | 744   | 744    | 744   | 1       |
| kiss                         | 69377           | 69377 | 69377  | 69377 | 1       |
| latestAnswer                 | 819             | 819   | 819    | 819   | 1       |
| latestRoundData              | 1311            | 1311  | 1311   | 1311  | 1       |
| poke                         | 31005           | 31005 | 31005  | 31005 | 1       |
| read                         | 860             | 860   | 860    | 860   | 1       |
| readWithAge                  | 735             | 735   | 735    | 735   | 1       |
| spread                       | 674             | 674   | 674    | 674   | 1       |
| stalenessThreshold           | 878             | 1878  | 1878   | 2878  | 2       |
| tryRead                      | 553             | 1553  | 1553   | 2553  | 2       |
| tryReadWithAge               | 1209            | 1209  | 1209   | 1209  | 1       |
```
