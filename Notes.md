## About 5.2 "Wrap Chainlink call into try-catch"

We didn't implement it due to a false sense of security.
If a malicious Chainlink contract update is performed, a `try-catch` block does
not a guarantee successful execution!

The only possible way to _really_ make sure the call cannot stop our execution
is via a low-level call with manual memory copying and capped gas given for
the execution.

Via `try-catch` following issues can still arise:
- Call returns data with incorrect length (or no data at all)
    - Not caught via `try-catch`
    - Reverts due to decoding issue
- Call uses all available gas
    - Can use up to 63/64 of remaining gas
    - If all gas used, remaining gas may won't be sufficient for entire execution

Note that even a default low-level call can be attacked via a return bomb attack.
The expected amount of return data would need to be manually hardcoded.
See for example [ExcessivelySafeCall](https://github.com/nomad-xyz/ExcessivelySafeCall/blob/main/src/ExcessivelySafeCall.sol#L8).

Due to this reasons we opted to not implement a strawman security mechanism and
favored less complexity.

## Decimals should be set to 8

Not every Chainlink oracle uses 8 decimals, especially _not_ the `stETH/ETH` oracle.
Note that we expected to use Chainlink's `stETH/ETH` oracle for the pegged version.

Now that we drop the asset mode, we can hardcode 8 decimals again imho.

