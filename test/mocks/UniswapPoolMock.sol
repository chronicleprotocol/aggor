// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract UniswapPoolMock {
    struct Observation {
        // the block timestamp of the observation
        uint32 blockTimestamp;
        // the tick accumulator, i.e. tick * time elapsed since the pool was first initialized
        int56 tickCumulative;
        // the seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
        uint160 secondsPerLiquidityCumulativeX128;
        // whether or not the observation is initialized
        bool initialized;
    }

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    Observation[65_535] public observations;

    address public token0;
    address public token1;

    bool shouldOverflowUint128;

    constructor() {
        slot0.observationCardinality = 300; // Copied cardinality from UniswapV3

        observations[0] = Observation(0, 0, 0, true);
    }

    function setShouldOverflowUint128(bool shouldOverflowUint128_) public {
        shouldOverflowUint128 = shouldOverflowUint128_;
    }

    function observe(uint32[] memory secondsAgo)
        public
        view
        returns (int56[] memory, uint160[] memory)
    {
        int56[] memory tickCumulatives = new int56[](2);
        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

        // forgefmt: disable-start
        if (shouldOverflowUint128) {
            // Provides a hardcoded price bigger than type(uint128).max.
            // Found via extensive fuzzing.
            // Price: 5172277991453938211655317709858723532690
            tickCumulatives[0] = -36028797018963967;
            tickCumulatives[1] = -36028753818877567;

            secondsPerLiquidityCumulativeX128s[0] = 0;
            secondsPerLiquidityCumulativeX128s[1] = 1;
        } else {
            // Provides a hardcoded price copied from the DAI/USDC 0.01% prool.
            // See https://etherscan.io/address/0x5777d92f208679db4b9778590fa3cab3ac9e2168#readContract.
            // Price: 999902
            tickCumulatives[0] = -19015290435809;
            tickCumulatives[1] = -19039164915809;

            secondsPerLiquidityCumulativeX128s[0] = 5758130429968257423961804564;
            secondsPerLiquidityCumulativeX128s[1] = 5758130494593330591803124245;
        }
        // forgefmt: disable-end

        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }

    function setSlot0(
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    ) public {
        slot0 = Slot0(
            sqrtPriceX96,
            tick,
            observationIndex,
            observationCardinality,
            observationCardinalityNext,
            feeProtocol,
            unlocked
        );
    }

    function setObservation(
        uint index,
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    ) public {
        require(index <= observations.length);

        observations[index] = Observation(
            blockTimestamp,
            tickCumulative,
            secondsPerLiquidityCumulativeX128,
            initialized
        );
    }

    function setToken0(address token) public {
        token0 = token;
    }

    function setToken1(address token) public {
        token1 = token;
    }
}
