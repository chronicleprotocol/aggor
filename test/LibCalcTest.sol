// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {LibCalc} from "src/libs/LibCalc.sol";

abstract contract LibCalcTest is Test {
    function test_scale_basic() public {
        uint scaled = LibCalc.scale(14_645_946_251_015_219_535, 18, 6);
        assertEq(scaled, 14_645_946);
        scaled = LibCalc.scale(14_645_946, 6, 18);
        assertEq(scaled, 14_645_946_000_000_000_000);

        assertEq(1 ether, LibCalc.scale(1 ether, 999, 999));
        assertEq(
            10_000_000_000_000_000_000_000_000_000_000_000_000_000,
            LibCalc.scale(1, 10, 50)
        );
    }

    function test_scale_revert() public {
        // No zeros allowed
        vm.expectRevert();
        LibCalc.scale(0, 1, 1);

        vm.expectRevert();
        LibCalc.scale(1, 0, 1);

        vm.expectRevert();
        LibCalc.scale(1, 1, 0);

        // Overflow/underflow
        vm.expectRevert();
        LibCalc.scale(12_345, 99, 1);

        vm.expectRevert();
        LibCalc.scale(100, 1000, 10_000);
    }

    function test_distance() public {
        assertEq(LibCalc.distance(1 ether, 2 ether), 1 ether);
        assertEq(LibCalc.distance(2.5 ether, 1 ether), 1.5 ether);
        assertEq(LibCalc.distance(0, 2 ^ 256 - 1), 2 ^ 256 - 1);
        assertEq(LibCalc.distance(2 ^ 256 - 1, 2 ^ 256 - 1), 0);
    }

    function test_pctDiff() public {
        assertEq(LibCalc.pctDiff(1 ether, 1.25 ether, 10_000), 2000); // 20.00%
        assertEq(LibCalc.pctDiff(1 ether, 1.25 ether, 100_000), 20_000); // 20.000%
        // Order doesn't matter, difference is the same
        assertEq(LibCalc.pctDiff(1.25 ether, 1 ether, 100_000), 20_000);
    }

    function testFuzz_unsafeMean(uint128 a, uint128 b) public {
        uint wantMean = (uint(a) + uint(b)) / 2;
        uint gotMean = LibCalc.unsafeMean(a, b);

        assertEq(wantMean, gotMean);
    }
}
