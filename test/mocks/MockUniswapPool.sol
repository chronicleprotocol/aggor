// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract MockUniswapPool {
    address internal _token0; // Should be of type IERC20
    address internal _token1; // Should be of type IERC20

    constructor(address token0_, address token1_) {
        _token0 = token0_;
        _token1 = token1_;
    }

    // -- IUniswapV3PoolImmutables Functionality --

    function token0() external view returns (address) {
        return _token0;
    }

    function token1() external view returns (address) {
        return _token1;
    }
}
