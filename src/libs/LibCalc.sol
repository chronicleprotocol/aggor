// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title LibCalc
 *
 * @notice Library for common calculations.
 */
library LibCalc {
    /// @dev Computes the percent difference of two numbers with a precision of
    ///      pscale (e.g. 10_000 == 99.99%).
    function pctDiff(uint128 a, uint128 b, uint pscale)
        internal
        pure
        returns (uint)
    {
        if (a == b) return 0;
        return a > b
            ? pscale - (((uint(b) * 1e18) / uint(a)) * pscale / 1e18)
            : pscale - (((uint(a) * 1e18) / uint(b)) * pscale / 1e18);
    }

    /// @dev Computes the numerical distance between two numbers. No overflow
    ///      worries here.
    function distance(uint a, uint b) internal pure returns (uint) {
        unchecked {
            return (a > b) ? a - b : b - a;
        }
    }

    /// @dev This allows you to scale uint decimals up or down, e.g. you can
    ///      scale a WETH value (decimals 18) to a USDT value (decimals 6)
    ///      and vice versa.
    function scale(uint n, uint dec, uint destDec)
        internal
        pure
        returns (uint)
    {
        require(n > 0 && dec > 0 && destDec > 0);
        require(n > dec && n > destDec);
        return destDec > dec
            ? n * (10 ** (destDec - dec)) // Scale up
            : n / (10 ** (dec - destDec)); // Scale down
    }

    /// @dev Optimized mean calculation at the expense of safety. Careful!
    function unsafeMean(uint a, uint b) internal pure returns (uint) {
        uint mean;
        unchecked {
            // Note that >> 1 equals a division by 2.
            mean = (a + b) >> 1;
        }
        return mean;
    }
}
