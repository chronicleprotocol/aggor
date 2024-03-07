# Aggor

This document provides technical documentation for _Chronicle Protocol_'s Aggor oracle system.

## Table of Contents

- [Aggor](#aggor)
  - [Table of Contents](#table-of-contents)
  - [Design Goals](#design-goals)
  - [Terminology](#terminology)
  - [Workflow](#workflow)
    - [Setup](#setup)
    - [Price Derivation](#price-derivation)

## Design Goals

- **Liveness**, ie Aggor should whenever possible provide a price
- **Resilient**, ie Aggor is adaptable and capable of handling multiple failure scenarios
- **Neutral**, ie Aggor does not depend on a single oracle provider

## Terminology

- An **Oracle** is defined as a push-based oracle system, eg _Chronicle Protocol_, Chainlink, etc.
- A **TWAP** is an onchain time weighted-average based oracle via which an asset's price can be derived without offchain components.
- An **oracle** (lower case) is a generic term that can refer to both a TWAP or an Oracle.
- The **agreement distance** is a mutable configuration defining the threshold until which Oracle values are defined as being in agreement.

## Workflow

_Note that Aggor's price derivation is generic and not bounded to its current specific implementation_.

### Setup

1. User defines the set of Oracles to use in Aggor
    - Note that at least 2 different Oracles MUST be set
2. User defines the TWAP to use in Aggor
3. User defines the agreement distance
    - Note that this value SHOULD be derived via historical analysis of the configured Oracle providers
4. User defines the age threshold
    - Note that this value SHOULD be derived based on the Oracle provider's update frequency

### Price Derivation

The following price derivation takes place during any of Aggor's read functions:

```
values := [read(oracle) for oracle in oracles]
values := filter(\v -> is_valid(v) and is_not_stale(v), values)

if len(values) >= 3:
    return median(values)  # Path: 1

if len(values) == 2:
    if in_agreement_distance(values):
        return median(values)  # Path: 2
    else:
        twap_value := read(twap)
        if is_valid(twap_value):
            return median(values ++ twap_value)  # Path: 3
        else:
            # Error: No value derivation possible
            return 0  # Path 6

if len(values) == 1:
    return values[0]  # Path: 4

if len(values) == 0:
    twap_value := read(twap)
    if is_valid(twap_value):
        return twap_value  # Path: 5
    else:
        # Error: No value derivation possible
        return 0  # Path: 6
```
