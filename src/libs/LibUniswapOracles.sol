// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {OracleLibrary} from
    "uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

/**
 * @title LibUniswapOracles
 *
 * @notice Library Uniswap oracle related functionality.
 */
library LibUniswapOracles {
    /// @notice Read the TWAP derived price from a Uniswap oracle.
    /// @dev The Uniswap pool address + pair addresses can be discovered at
    ///      https://app.uniswap.org/#/swap
    /// @param uniPool The Uniswap pool that wil be observed.
    /// @param uniBasePair The base pair for the pool, e.g. WETH in WETHUSDT.
    /// @param uniQuotePair The quote pair for the pool, e.g. USDT in WETHUSDT.
    /// @param uniBaseDec The decimals of the base pair ERC-20 token.
    /// @param secondsAgo The time in seconds to "look back" per TWAP.
    function readOracle(
        address uniPool,
        address uniBasePair,
        address uniQuotePair,
        uint8 uniBaseDec,
        uint32 secondsAgo
    ) internal view returns (uint) {
        (int24 tick,) = OracleLibrary.consult(address(uniPool), secondsAgo);

        // Calculate exactly 1 unit of the base pair for quote
        uint128 amt = uint128(1 * (10 ** uniBaseDec));

        uint val =
            OracleLibrary.getQuoteAtTick(tick, amt, uniBasePair, uniQuotePair);
        return val;
    }
}
