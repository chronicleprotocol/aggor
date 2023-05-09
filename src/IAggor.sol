// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";

interface IAggor is IChronicle {
    /// @notice Thrown if an oracle read fails.
    /// @param oracle The oracle address which read's failed.
    error OracleReadFailed(address oracle);

    /// @notice Emitted when staleness threshold updated.
    /// @param oldStalenessThreshold The old staleness threshold.
    /// @param newStalenessThreshold The new staleness threshold.
    event StalenessThresholdUpdated(
        address indexed caller,
        uint oldStalenessThreshold,
        uint newStalenessThreshold
    );

    /// @notice Emitted when Chainlink's oracle delivered a stale value.
    /// @param age The age of Chainlink's oracle value.
    /// @param timestamp The timestamp when the Chainlink oracle was read.
    event ChainlinkValueStale(uint age, uint timestamp);

    /// @notice Emitted when Chainlink's oracle delivered a negative value.
    /// @param value The value the Chainlink oracle delivered.
    event ChainlinkValueNegative(int value);

    /// @notice Emitted when Chainlink's oracle delivered a zero value.
    event ChainlinkValueZero();

    /// @notice The Chronicle oracle to aggregate.
    /// @return The address of the Chronicle oracle being aggregated.
    function chronicle() external view returns (address);

    /// @notice The Chainlink oracle to aggregate.
    /// @return The address of the Chainlink oracle being aggregated.
    function chainlink() external view returns (address);

    /// @notice Pokes aggor, i.e. updates aggor's value to the mean of
    ///         Chronicle's and Chainlink's current values.
    /// @dev Reverts if an oracle's value cannot be read.
    /// @dev Reverts if an oracle's value is zero.
    /// @dev Reverts if Chainlink's oracle value is negative.
    /// @dev Reverts if Chainlink's oracle value is stale as being defined via
    ///      staleness threshold.
    function poke() external;

    /// @notice Returns the oracle's latest value.
    /// @dev Provides partial compatibility to Chainlink's
    ///      IAggregatorV3Interface.
    /// @return roundId 0.
    /// @return answer The oracle's latest value.
    /// @return startedAt 0.
    /// @return updatedAt The timestamp of oracle's latest update.
    /// @return answeredInRound 0.
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
    function stalenessThreshold() external view returns (uint);

    /// @notice Updates the staleness threshold parameter to
    ///         `stalenessThreshold`.
    /// @dev Only callable by auth'ed address.
    /// @dev Reverts if `stalenessThreshold` is zero.
    /// @param stalenessThreshold The value to update stalenessThreshold to.
    function setStalenessThreshold(uint stalenessThreshold) external;
}
