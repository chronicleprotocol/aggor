![](./assets/title.png)

Aggregate Oracle that combines the prices of multiple sources into a mean value. Resiliency and distributed trust.

# Overview

The `AggregateOracle` contract has two basic functions:

## poke()

The `poke()` function pulls the price from the price _sources_ and if there is no error getting the price, generates and stores the average of those prices. If there ever is an error retrieving a price from a source, the mean price will not be updated. In this way we ensure that (1) we always provide a price, and (2) in the event of an error we do not update the price with a bad price. This has the implication that while we don't provide a bad price we MAY provide a stale price.

## readWithAge()

The recommended way to access the value produced by `poke()` is 

```
    function readWithAge() external view toll returns (uint256, uint256)
```

It returns the `price` along with an epoch (`block.timestamp`) for when the price was updated. This way any consumer can reason about how _fresh_ is the price they received.

## Compatibility

Because this contract provides the price of more than one oracle source (currently Chronicle and Chainlink), we provide compatibility functions for consumers of one or the other source. This way no code modifications are required for any customer who wants to switch to the aggregate oracle.

### Maker/Chronicle

If the consumer is using the Maker style median oracle, they can use 

```
function read() external view returns (uint256)
```

If the consumer is using Chainlink oracles, the following compatibility functions are available:

```
function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
function latestAnswer() external view returns (int256); // deprecated
```

Note that in all cases, we are returning the _mean_ value of the two sources, UNLESS there was a deviation from one oracle source, in which we will defer to the other source.

# Gas report

```
Gas report taken Wed May 10 17:44:18 UTC 2023
forge t --gas-report --match-test poke_basic
[⠒] Compiling...
No files changed, compilation skipped

Running 1 test for test/Aggor.t.sol:AggorTest
[PASS] test_poke_basic(uint128,uint128,uint256,uint256) (runs: 256, μ: 137921, ~: 136802)
Test result: ok. 1 passed; 0 failed; finished in 35.61ms
| src/Aggor.sol:Aggor contract |                 |       |        |       |         |
|------------------------------|-----------------|-------|--------|-------|---------|
| Deployment Cost              | Deployment Size |       |        |       |         |
| 1218100                      | 6120            |       |        |       |         |
| Function Name                | min             | avg   | median | max   | # calls |
| chainlink                    | 488             | 488   | 488    | 488   | 1       |
| chronicle                    | 532             | 532   | 532    | 532   | 1       |
| kiss                         | 69099           | 69099 | 69099  | 69099 | 1       |
| latestAnswer                 | 645             | 645   | 645    | 645   | 1       |
| latestRoundData              | 1046            | 1046  | 1046   | 1046  | 1       |
| poke                         | 29949           | 29949 | 29949  | 29949 | 1       |
| read                         | 686             | 686   | 686    | 686   | 1       |
| readWithAge                  | 605             | 605   | 605    | 605   | 1       |
| stalenessThreshold           | 2654            | 2654  | 2654   | 2654  | 1       |
| tryRead                      | 511             | 1511  | 1511   | 2511  | 2       |
| tryReadWithAge               | 969             | 969   | 969    | 969   | 1       |
```