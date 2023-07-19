// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {MockIChronicle} from "./mocks/MockIChronicle.sol";
import {MockIChainlinkAggregatorV3} from
    "./mocks/MockIChainlinkAggregatorV3.sol";
import {MockUniswapPool} from "./mocks/MockUniswapPool.sol";
import {MockIERC20} from "./mocks/MockIERC20.sol";

// -- Aggor Tests --

import {Aggor} from "src/Aggor.sol";

import {IAggorTest} from "./IAggorTest.sol";

contract AggorTest is IAggorTest {
    MockUniswapPool uniPool;
    MockIERC20 uniPoolToken0;
    MockIERC20 uniPoolToken1;

    function setUp() public {
        uniPoolToken0 =
            new MockIERC20("Uniswap Pool Token 0", "UniToken0", uint8(18));
        uniPoolToken1 =
            new MockIERC20("Uniswap Pool Token 1", "UniToken1", uint8(18));
        uniPool =
            new MockUniswapPool(address(uniPoolToken0), address(uniPoolToken1));

        setUp(
            new Aggor(
                address(new MockIChronicle()),
                address(new MockIChainlinkAggregatorV3()),
                address(uniPool),
                true
            )
        );
    }
}

// -- Library Tests --

import {LibCalcTest as LibCalcTest_} from "./LibCalcTest.sol";

contract LibCalcTest is LibCalcTest_ {}
