// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {LibUniswapOracles} from "src/libs/LibUniswapOracles.sol";

contract LibUniswapOraclesIntegrationTest is Test {
    LibUniswapOraclesWrapper wrapper;

    // Using the USDC/DAI 0.01% pool.
    address pool = address(0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168);
    address baseToken = address(0x6B175474E89094C44Da98b954EedeAC495271d0F); // DAI
    address quoteToken = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
    uint8 baseDecimals = 18; // DAI.decimals()
    uint32 lookback = 1 hours;

    function test_readOracle() public {
        // Start mainnet fork.
        vm.createSelectFork("eth");

        // Note to deploy after fork initiated.
        wrapper = new LibUniswapOraclesWrapper();

        uint price = wrapper.readOracle(
            pool, baseToken, quoteToken, baseDecimals, lookback
        );

        // DAI/USDC is ~1 USD denominated in USDC, ie 6 decimals.
        uint want = 1e6;

        // We expect DAI/USDC to be max 10% off.
        assertApproxEqAbs(price, want, 1e5);
    }

    function test_getOldestObservationSecondsAgo() public {
        // Start mainnet fork.
        vm.createSelectFork("eth");

        // Note to deploy after fork initiated.
        wrapper = new LibUniswapOraclesWrapper();

        uint32 oldest = wrapper.getOldestObservationSecondsAgo(pool);
        assertTrue(oldest > 100 days);
    }
}

/**
 * @notice Library wrapper to enable forge coverage reporting
 *
 * @dev For more info, see https://github.com/foundry-rs/foundry/pull/3128#issuecomment-1241245086.
 */
contract LibUniswapOraclesWrapper {
    function readOracle(
        address pool,
        address baseToken,
        address quoteToken,
        uint8 baseDecimals,
        uint32 lookback
    ) public view returns (uint) {
        return LibUniswapOracles.readOracle(
            pool, baseToken, quoteToken, baseDecimals, lookback
        );
    }

    function getOldestObservationSecondsAgo(address pool)
        public
        view
        returns (uint32)
    {
        return LibUniswapOracles.getOldestObservationSecondsAgo(pool);
    }
}
