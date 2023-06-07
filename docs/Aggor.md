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

## Benchmarks

A gas report for the `poke()` function can be created via `make gas_report`.

```bash
$ make gas_report

Gas report taken Wed Jun  7 10:45:35 UTC 2023
forge t --gas-report --match-test poke_basic
[⠒] Compiling...
No files changed, compilation skipped

Running 1 test for test/Runner.t.sol:AggorTest
[PASS] testFuzz_poke_basic(uint128,uint128,uint256,uint256,uint256) (runs: 256, μ: 167561, ~: 167689)
Test result: ok. 1 passed; 0 failed; finished in 49.07ms
| src/Aggor.sol:Aggor contract |                 |       |        |       |         |
|------------------------------|-----------------|-------|--------|-------|---------|
| Deployment Cost              | Deployment Size |       |        |       |         |
| 2334115                      | 12122           |       |        |       |         |
| Function Name                | min             | avg   | median | max   | # calls |
| chainlink                    | 678             | 678   | 678    | 678   | 1       |
| chronicle                    | 722             | 722   | 722    | 722   | 1       |
| kiss                         | 69382           | 69382 | 69382  | 69382 | 1       |
| latestAnswer                 | 769             | 769   | 769    | 769   | 1       |
| latestRoundData              | 1283            | 1283  | 1283   | 1283  | 1       |
| poke                         | 33036           | 33036 | 33036  | 33036 | 1       |
| read                         | 810             | 810   | 810    | 810   | 1       |
| readWithAge                  | 707             | 707   | 707    | 707   | 1       |
| spread                       | 630             | 630   | 630    | 630   | 1       |
| stalenessThreshold           | 856             | 1856  | 1856   | 2856  | 2       |
| tryRead                      | 525             | 1525  | 1525   | 2525  | 2       |
| tryReadWithAge               | 1181            | 1181  | 1181   | 1181  | 1       |
```
