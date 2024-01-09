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
    /// @dev Reads the TWAP derived price from a Uniswap oracle.
    ///
    /// @dev The Uniswap pool address + pair addresses can be discovered at
    ///      https://app.uniswap.org/#/swap
    /// @param pool The Uniswap pool that wil be observed.
    /// @param baseToken The base token for the pool, e.g. WETH in WETHUSDT.
    /// @param quoteToken The quote pair for the pool, e.g. USDT in WETHUSDT.
    /// @param baseDecimals The decimals of the base pair ERC-20 token.
    /// @param lookback The time in seconds to look back per TWAP.
    function _readOracle(
        address pool,
        address baseToken,
        address quoteToken,
        uint8 baseDecimals,
        uint32 lookback
    ) internal view returns (uint) {
        (int24 tick,) = OracleLibrary.consult(address(pool), lookback);

        // Calculate exactly 1 unit of the base pair for quote.
        uint128 amt = uint128(10 ** baseDecimals);

        // Use Uniswap's periphery library to get quote.
        return OracleLibrary.getQuoteAtTick(tick, amt, baseToken, quoteToken);
    }
}
