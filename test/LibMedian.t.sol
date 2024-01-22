// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {LibMedian} from "src/libs/LibMedian.sol";

contract LibMedianTest is Test {
    LibMedianWrapper wrapper = new LibMedianWrapper();

    function test_median_2() public {
        uint128 a;
        uint128 b;
        uint128 want;
        uint128 got;

        // median(0, 0) = 0
        a = 0;
        b = 0;
        want = 0;
        got = wrapper.median(a, b);
        assertEq(got, want);

        // median(type(uint128).max, type(uint128).max) = type(uint128).max
        a = type(uint128).max;
        b = type(uint128).max;
        want = type(uint128).max;
        got = wrapper.median(a, b);
        assertEq(got, want);

        // median(type(uint128).max, 0) = type(uint128).max / 2
        a = type(uint128).max;
        b = 0;
        want = type(uint128).max / 2;
        got = wrapper.median(a, b);
        assertEq(got, want);

        // median(0, type(uint128).max) = type(uint128).max / 2
        a = 0;
        b = type(uint128).max;
        want = type(uint128).max / 2;
        got = wrapper.median(a, b);
        assertEq(got, want);
    }

    function testFuzz_median_2(uint128 a, uint128 b) public {
        uint128 want = uint128((uint(a) + uint(b)) / 2);
        uint128 got = wrapper.median(a, b);
        assertEq(got, want);
    }

    function test_median_3() public {
        uint128 a;
        uint128 b;
        uint128 c;
        uint128 got;
        uint128 want;

        // median(0, 0, 0) = 0
        a = 0;
        b = 0;
        c = 0;
        want = 0;
        got = wrapper.median(a, b, c);
        assertEq(got, want);

        // median(type(uint128).max, type(uint128).max, type(uint128).max) = type(uint128).max
        a = type(uint128).max;
        b = type(uint128).max;
        c = type(uint128).max;
        want = type(uint128).max;
        got = wrapper.median(a, b, c);
        assertEq(got, want);

        // median(1, 2, 3) = 2
        a = 1;
        b = 2;
        c = 3;
        want = 2;
        got = wrapper.median(a, b, c);
        assertEq(got, want);

        // median(1, 1, 2) = 1
        a = 1;
        b = 1;
        c = 2;
        want = 1;
        got = wrapper.median(a, b, c);
        assertEq(got, want);

        // median(1, 2, 2) = 2
        a = 1;
        b = 2;
        c = 2;
        want = 2;
        got = wrapper.median(a, b, c);
        assertEq(got, want);
    }

    function testFuzz_median_3(uint128 a, uint128 b, uint128 c) public {
        uint want;
        if (a <= b && b <= c) want = b;
        else if (c <= b && b <= a) want = b;
        else if (b <= a && a <= c) want = a;
        else if (c <= a && a <= b) want = a;
        else if (a <= c && c <= b) want = c;
        else if (b <= c && c <= a) want = c;
        else revert("Unreachable");

        uint got = wrapper.median(a, b, c);
        assertEq(got, want);
    }
}

/**
 * @notice Library wrapper to enable forge coverage reporting
 *
 * @dev For more info, see https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086.
 */
contract LibMedianWrapper {
    function median(uint128 a, uint128 b) public pure returns (uint128) {
        return LibMedian.median(a, b);
    }

    function median(uint128 a, uint128 b, uint128 c)
        public
        pure
        returns (uint128)
    {
        return LibMedian.median(a, b, c);
    }
}
