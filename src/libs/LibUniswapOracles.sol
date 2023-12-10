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
    ///      expects the base token amount as type uint128.
    uint internal constant MAX_UNI_BASE_DEC = 38;

    /// @dev Reads the TWAP derived price from a Uniswap oracle.
    ///
    /// @dev The Uniswap pool address + pair addresses can be discovered at
    ///      https://app.uniswap.org/#/swap
    /// @param pool The Uniswap pool that wil be observed.
    /// @param baseToken The base token for the pool, e.g. WETH in WETHUSDT.
    /// @param quoteToken The quote pair for the pool, e.g. USDT in WETHUSDT.
    /// @param baseDecimals The decimals of the base pair ERC-20 token.
    /// @param lookback The time in seconds to look back per TWAP.
    function readOracle(
        address pool,
        address baseToken,
        address quoteToken,
        uint8 baseDecimals,
        uint32 lookback
    ) internal view returns (uint) {
        // Note that 10**(MAX_UNI_BASE_DEC + 1) would overflow type uint128.
        require(baseDecimals <= MAX_UNI_BASE_DEC);

        (int24 tick,) = OracleLibrary.consult(address(pool), lookback);

        // Calculate exactly 1 unit of the base pair for quote.
        uint128 amt = uint128(10 ** baseDecimals);

        // Use Uniswap's periphery library to get quote.
        return OracleLibrary.getQuoteAtTick(tick, amt, baseToken, quoteToken);
    }
}
