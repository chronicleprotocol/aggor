// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Aggor} from "src/Aggor.sol";

import {IAggorTest} from "./IAggorTest.sol";
import {LibCalcTest as LibCalcTest_} from "./LibCalcTest.sol";

import {MockIChronicle} from "./mocks/MockIChronicle.sol";
import {MockIChainlinkAggregatorV3} from
    "./mocks/MockIChainlinkAggregatorV3.sol";

contract AggorTest is IAggorTest {
    function setUp() public {
        setUp(
            new Aggor(
                address(new MockIChronicle()),
                address(new MockIChainlinkAggregatorV3())
            )
        );
    }
}

contract LibCalcTest is LibCalcTest_ {}