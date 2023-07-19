// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract MockUniswapPool {
    address internal _token0; // Should be of type IERC20
    address internal _token1; // Should be of type IERC20
    int56[] internal tickCumulatives;
    uint160[] internal secondsPerLiquidityCumulativeX128s;

    constructor(address token0_, address token1_) {
        _token0 = token0_;
        _token1 = token1_;

        // @todo For better test coverage we should add the ability to
        //       configure these values. Currently we're just using these
        //       static values obtained from an actual Uniswap pool.
        tickCumulatives =
            [int56(-13_916_113_000_655), int56(-13_916_173_262_387)];
        secondsPerLiquidityCumulativeX128s = [
            uint160(765_477_856_542_428_689_888_050_014_397),
            uint160(765_477_865_195_500_996_853_711_067_727)
        ];
    }

    // -- IUniswapV3PoolImmutables Functionality --

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }

    function observe(uint32[] calldata)
        external
        view
        returns (int56[] memory, uint160[] memory)
    {
        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }
}
