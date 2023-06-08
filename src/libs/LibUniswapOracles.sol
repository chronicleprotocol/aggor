// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {OracleLibrary} from
    "uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

/**
 * @title LibUniswapOracles
 *
 * @notice Library for Uniswap oracle related functionality.
 */
library LibUniswapOracles {
    /// @dev The maximum number of decimals for the base asset supported.
    ///      Note that this constraint comes from Uniswap's OracleLibrary which
    ///      takes the base asset amount as type uint128.
    uint internal constant MAX_UNI_BASE_DEC = 38;

    /// @notice Reads the TWAP derived price from a Uniswap oracle.
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
        // Note that 10**(MAX_UNI_BASE_DEC + 1) would overflow type uint128.
        require(uniBaseDec <= MAX_UNI_BASE_DEC);

        (int24 tick,) = OracleLibrary.consult(address(uniPool), secondsAgo);

        // Calculate exactly 1 unit of the base pair for quote
        uint128 amt = uint128(1 * (10 ** uniBaseDec));

        uint val =
            OracleLibrary.getQuoteAtTick(tick, amt, uniBasePair, uniQuotePair);
        return val;
    }
}
