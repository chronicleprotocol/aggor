// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IAggor {
    /// @notice Status encapsulates Aggor's value derivation path.
    /// @custom:field path The path identifier.
    /// @custom:field goodOracleCtr The number of oracles used to derive the
    ///                             value.
    struct Status {
        uint path;
        uint goodOracleCtr;
    }

    /// @notice Emitted when agreement distance is updated.
    /// @param caller The caller's address.
    /// @param oldAgreementDistance Old agreement distance
    /// @param newAgreementDistance New agreement distance
    event AgreementDistanceUpdated(
        address indexed caller,
        uint oldAgreementDistance,
        uint newAgreementDistance
    );

    /// @notice Emitted when age threshold updated.
    /// @param caller The caller's address.
    /// @param oldAgeThreshold Old age threshold.
    /// @param newAgeThreshold New age threshold.
    event AcceptableAgeThresholdUpdated(
        address indexed caller, uint oldAgeThreshold, uint newAgeThreshold
    );

    // -- Chainlink Compatibility --

    /// @notice Returns the number of decimals of the oracle's value.
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
    function latestAnswer() external view returns (int answer);

    // -- Other Read Functions --

    /// @notice Returns the oracle's latest value and status information.
    /// @return val The oracle's value.
    /// @return age The value's age.
    /// @return status The status information.
    function readWithStatus()
        external
        view
        returns (uint val, uint age, Status memory status);

    // -- Immutable Configurations --

    // -- Oracles

    /// @notice Returns the Chronicle oracle.
    /// @return chronicle The Chronicle oracle address.
    function chronicle() external view returns (address chronicle);

    /// @notice Returns the Chainlink oracle.
    /// @return chainlink The Chainlink oracle address.
    function chainlink() external view returns (address chainlink);

    // -- Uniswap TWAP

    /// @notice Returns the Uniswap pool used as twap.
    /// @return pool The Uniswap pool.
    function uniswapPool() external view returns (address pool);

    /// @notice Returns the Uniswap pool's base token.
    /// @return baseToken The Uniswap pool's base token.
    function uniswapBaseToken() external view returns (address baseToken);

    /// @notice Returns the Uniswap pool's quote token.
    /// @return quoteToken The Uniswap pool's quote token.
    function uniswapQuoteToken() external view returns (address quoteToken);

    /// @notice Returns the Uniswap pool's base token's decimals.
    /// @return baseTokenDecimals The Uniswap pool's base token's decimals.
    function uniswapBaseTokenDecimals()
        external
        view
        returns (uint8 baseTokenDecimals);

    /// @notice Returns the time in seconds to use as lookback for Uniswap Twap
    ///         oracle.
    /// @return lookback The time in seconds to use as lookback.
    function uniswapLookback() external view returns (uint32 lookback);

    // -- Mutable Configurations --

    /// @notice Returns the agreement distance in WAD used to determine whether
    ///         a set of oracle values are in agreement.
    /// @return agreementDistance The agreement distance.
    function agreementDistance()
        external
        view
        returns (uint128 agreementDistance);

    /// @notice The acceptable age of price that will be allowed.
    /// @return ageThreshold The time in seconds where a price is considered
    ///                      non-stale.
    function ageThreshold() external view returns (uint32 ageThreshold);

    // -- Auth'ed Functionality --

    /// @notice Sets the agreement distance.
    /// @dev Only callable by auth'ed addresses.
    function setAgreementDistance(uint128 agreementDistance) external;

    /// @notice Sets the age threshold.
    /// @dev Only callable by auth'ed addresses.
    function setAgeThreshold(uint32 ageThreshold) external;
}
