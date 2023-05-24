// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IToll} from "chronicle-std/toll/IToll.sol";

import "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import {LibCalc} from "src/libs/LibCalc.sol";
import {LibUniswapOracles} from "src/libs/LibUniswapOracles.sol";
import {Aggor} from "src/Aggor.sol";

import {MockIChronicle} from "./mocks/MockIChronicle.sol";
import {MockIChainlinkAggregatorV3} from
    "./mocks/MockIChainlinkAggregatorV3.sol";

// Integration test queries the real Uniswap WETHUSDT pool and verifies mean.
contract MainnetIntegrationTest is Test {
    /// @dev Uniswap pool
    address constant UNI_POOL_WETHUSDT =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;

    /// @dev WETH ERC-20 contract
    address constant UNI_TOKEN_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev USDT ERC-20 contract
    address constant UNI_TOKEN_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @dev Decimals of base pair
    uint8 constant BASE_DEC = 18;

    /// @dev Decimals of quote pair
    uint8 constant QUOTE_DEC = 6;

    Aggor aggor;
    MockIChronicle chronicle;

    function setUp() public {
        // Create mainnet fork.
        vm.createSelectFork("mainnet");

        // Deploy and kiss
        chronicle = new MockIChronicle();
        aggor = new Aggor(
            address(chronicle),
            address(new MockIChainlinkAggregatorV3())
        );
        IToll(address(aggor)).kiss(address(this));
        aggor.setUniswap(UNI_POOL_WETHUSDT);
    }

    function testIntegration_Mainnet() public {
        uint curr = LibUniswapOracles.readOracle(
            UNI_POOL_WETHUSDT, UNI_TOKEN_WETH, UNI_TOKEN_USDT, BASE_DEC, 300
        );
        assertTrue(curr > 0);

        curr = LibCalc.scale(curr, QUOTE_DEC, BASE_DEC);
        uint cval = (curr / 10) * 9; // Reduce by 10%
        console2.log("Uniswap WETHUSDT:   ", curr);
        console2.log("Chronicle WETHUSDT: ", cval);

        chronicle.setVal(cval);
        chronicle.setAge(block.timestamp);

        // This spread will cause failure and selection of Chronicle value
        aggor.setSpread(999);
        aggor.poke();
        console2.log("Nearest:            ", aggor.read());
        assertEq(aggor.read(), cval);

        // Set spread to 10.00% so we get the mean
        aggor.setSpread(1000);
        aggor.poke();
        console2.log("Mean:               ", aggor.read());
        assertEq(aggor.read(), (cval + curr) / 2);
    }
}
