// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";

interface IAggor is IChronicle {
    /// @notice Thrown if an oracle read fails.
    /// @param oracle The oracle address which read's failed.
    error OracleReadFailed(address oracle);

    /// @notice Emitted when Uniswap TWAP pool updated.
    /// @param caller The caller's address.
    /// @param oldUniswapPool The old Uniswap pool address.
    /// @param newUniswapPool The new Uniswap pool address.
    event UniswapUpdated(
        address indexed caller, address oldUniswapPool, address newUniswapPool
    );

    /// @notice Emitted when staleness threshold updated.
    /// @param caller The caller's address.
    /// @param oldStalenessThreshold The old staleness threshold.
    /// @param newStalenessThreshold The new staleness threshold.
    event StalenessThresholdUpdated(
        address indexed caller,
        uint32 oldStalenessThreshold,
        uint32 newStalenessThreshold
    );

    /// @notice Emitted when spread is updated.
    /// @param caller The caller's address.
    /// @param oldSpread The old spread value.
    /// @param newSpread The new spread value.
    event SpreadUpdated(
        address indexed caller, uint16 oldSpread, uint16 newSpread
    );

    /// @notice Emitted when Uniswap TWAP's lookback period is updated.
    /// @param caller The caller's address.
    /// @param oldUniswapSecondsAgo The old uniswapSecondsAgo value.
    /// @param newUniswapSecondsAgo The new uniswapSecondsAgo value.
    event UniswapSecondsAgoUpdated(
        address indexed caller,
        uint32 oldUniswapSecondsAgo,
        uint32 newUniswapSecondsAgo
    );

    /// @notice Emitted when Chronicle's oracle delivered a stale value.
    /// @param age The age of Chronicle's oracle value.
    /// @param timestamp The timestamp when the Chronicle oracle was read.
    event ChronicleValueStale(uint age, uint timestamp);

    /// @notice Emitted when Chainlink's oracle delivered a stale value.
    /// @param age The age of Chainlink's oracle value.
    /// @param timestamp The timestamp when the Chainlink oracle was read.
    event ChainlinkValueStale(uint age, uint timestamp);

    /// @notice Emitted when Chainlink's oracle delivered a negative value.
    /// @param value The value the Chainlink oracle delivered.
    event ChainlinkValueNegative(int value);

    /// @notice Emitted when Chainlink's oracle delivered a zero value.
    event ChainlinkValueZero();

    /// @notice Emitted when Uniswap's oracle delivered a zero value.
    event UniswapValueZero();

    /// @notice Emitted when Uniswap's oracle has not been setup.
    event UniswapNotConfigured();

    /// @notice The Chronicle oracle to aggregate.
    /// @return The address of the Chronicle oracle being aggregated.
    function chronicle() external view returns (address);

    /// @notice The Chainlink oracle to aggregate.
    /// @return The address of the Chainlink oracle being aggregated.
    function chainlink() external view returns (address);

    /// @notice The Uniswap pool that wil be observed.
    function uniPool() external view returns (address);

    /// @notice The base pair for the pool, e.g. WETH in WETHUSDT.
    function uniBasePair() external view returns (address);

    /// @notice The quote pair for the pool, e.g. USDT in WETHUSDT.
    function uniQuotePair() external view returns (address);

    /// @notice The decimals of the base pair ERC-20 token.
    function uniBaseDec() external view returns (uint8);

    /// @notice The decimals of the quote pair ERC-20 token.
    function uniQuoteDec() external view returns (uint8);

    /// @notice The time in seconds to "look back" per TWAP.
    function uniSecondsAgo() external view returns (uint32);

    /// @notice The minimum allowed lookback period for the Uniswap TWAP.
    /// @dev The minimum allowed value for uniSecondsAgo.
    function minUniSecondsAgo() external view returns (uint32);

    /// @notice Pokes aggor, i.e. updates aggor's value to the mean of
    ///         Chronicle's and Chainlink's current values.
    /// @dev Reverts if an oracle's value cannot be read.
    /// @dev Reverts if an oracle's value is zero.
    /// @dev Reverts if Chainlink's oracle value is negative.
    /// @dev Reverts if Chainlink's oracle value is stale as being defined via
    ///      staleness threshold.
    function poke() external;

    /// @notice Returns the number of decimals of the oracle's value.
    /// @dev Provides partial compatibility with Chainlink's
    ///      IAggregatorV3Interface.
    /// @return decimals The oracle value's number of decimals.
    function decimals() external view returns (uint8 decimals);

    /// @notice Returns the oracle's latest value.
    /// @dev Provides partial compatibility to Chainlink's
    ///      IAggregatorV3Interface.
    /// @return roundId 1.
    /// @return answer The oracle's latest value.
    /// @return startedAt 0.
    /// @return updatedAt The timestamp of oracle's latest update.
    /// @return answeredInRound 1.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        );

    /// @notice Returns the oracle's latest value.
    /// @custom:deprecated See https://docs.chain.link/data-feeds/api-reference/#latestanswer.
    /// @return answer The oracle's latest value.
    function latestAnswer() external view returns (int);

    /// @notice Defines the allowed age of an oracle's value before being
    ///         declared stale.
    /// @return The staleness threshold parameter.
    function stalenessThreshold() external view returns (uint32);

    /// @notice Updates the staleness threshold parameter to
    ///         `stalenessThreshold`.
    /// @dev Only callable by auth'ed address.
    /// @dev Reverts if `stalenessThreshold` is zero.
    /// @param stalenessThreshold The value to update stalenessThreshold to.
    function setStalenessThreshold(uint32 stalenessThreshold) external;

    /// @notice The percentage difference between the price gotten from
    ///         oracles, used as a trigger to detect a potentially
    ///         compromised oracle.
    /// @dev The percent spread (difference in price) we can tolerate between
    ///      sources. If the difference is over this amount, assume one of the
    ///      sources is sussy. Defaults to 5%. Acceptable range 0 - 9999 (99.99%).
    /// @return The spread as a percentage difference between oracle prices
    function spread() external view returns (uint16);

    /// @notice Updates the spread parameter to `spread`.
    /// @dev Only callable by auth'ed address.
    /// @dev Revert is `spread` is more than 10000.
    /// @param spread The value to which to update spread.
    function setSpread(uint16 spread) external;

    /// @notice Switch from default oracle (Chainlink) to alt (Uniswap),
    ///         and back.
    /// @dev Only callable by auth'ed address.
    /// @param uniPool Provide the address to the Uniswap pool. If set to
    //         address(0) Uniswap will not be used.
    function setUniswap(address uniPool) external;

    /// @notice Set the Uniswap TWAP lookback period. If never called, default
    //          is 5m.
    /// @dev Only callable by auth'ed address.
    /// @dev Reverts if uniSecondsAgo less than minUniSecondsAgo.
    /// @param uniSecondsAgo Time in seconds used in the TWAP lookback.
    function setUniSecondsAgo(uint32 uniSecondsAgo) external;
}
