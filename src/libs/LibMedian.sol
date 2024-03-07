// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

/**
 * @title LibMedian
 *
 * @notice Library to efficiently compute medians.
 */
library LibMedian {
    function median(uint128 a, uint128 b) internal pure returns (uint128) {
        // Note to cast arguments to uint to avoid overflow possibilites.
        uint sum;
        unchecked {
            sum = uint(a) + uint(b);
        }
        // assert(sum <= 2 * type(uint128).max);

        // Note that >> 1 equals a divison by 2.
        return uint128(sum >> 1);
    }

    function median(uint128 a, uint128 b, uint128 c)
        internal
        pure
        returns (uint128)
    {
        if (a < b) {
            if (b < c) {
                // a < b < c
                return b;
            } else {
                // a < b && c <= b
                return a > c ? a : c;
            }
        } else {
            if (a < c) {
                // b <= a < c
                return a;
            } else {
                // b <= a && c <= a
                return b > c ? b : c;
            }
        }
    }
}
