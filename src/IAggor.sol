// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";

interface IAggor is IChronicle {
    /// @notice Returns the number of decimals of the oracle's value.
    /// @return decimals The oracle value's number of decimals.
    function decimals() external view returns (uint8);

    /// @notice Returns the agreement distance (%) used to determine if Oracle
    ///         prices are "in agreement".
    /// @return agreementDistance The agreement distance.
    function agreementDistance() external view returns (uint);

    /// @notice If true, the contract pair (wat) is a 1:1 pegged asset.
    /// @return isPeggedAsset Whether the asset pair is pegged or not.
    function isPeggedAsset() external view returns (bool);

    /// @notice Returns the set of addresses that constitute external Oracles.
    /// @return oracles The set of Oracles used to obtain price.
    function oracles() external view returns (address[] memory);

    /// @notice The address of the tie-breaking TWAP instance.
    /// @return twap Address of TWAP interface contract.
    function twap() external view returns (address);

    /// @notice The acceptable age of price that will be allowed.
    /// @return acceptableAgeThreshold The time in seconds where a price is
    //          considered "fresh".
    function acceptableAgeThreshold() external view returns (uint);

    /// @notice As price is determined during read this struct tracks
    ///         information about how the price was obtained.
    /// @param returnLevel The point along the degradation path at which the
    ///        price was returned. Lower is better, i.e. 1 is better than 6.
    /// @param countGoodOraclePrices The number of Oracles that returned a trustworthy price.
    /// @param countFailedOraclePrices The number of Oracles that returned a bad price.
    /// @param twapUsed Flag as to whether TWAP had to be used as a tie-breaker.
    struct StatusInfo {
        uint returnLevel;
        uint countGoodOraclePrices;
        uint countFailedOraclePrices;
        bool twapUsed;
    }

    /// @notice Emitted when the agreement distance is changed.
    /// @param caller The caller's address
    /// @param oldAgreementDistance Current agreement distance
    /// @param newAgreementDistance Updated agreement distance
    event AgreementDistanceUpdated(
        address indexed caller,
        uint oldAgreementDistance,
        uint newAgreementDistance
    );

    /// @notice Emitted when the acceptable age for price is changed.
    /// @param caller The caller's address
    /// @param oldAcceptableAgeThreshold Current acceptable age
    /// @param newAcceptableAgeThreshold Updated acceptable age
    event AcceptableAgeThresholdUpdated(
        address indexed caller,
        uint oldAcceptableAgeThreshold,
        uint newAcceptableAgeThreshold
    );

    /// @notice Emitted when Oracle set is changed.
    /// @param caller The caller's address
    /// @param oldLen Current number of Oracles
    /// @param newLen Updated number of Oracles
    event OraclesUpdated(address indexed caller, uint oldLen, uint newLen);

    /// @notice Emitted when TWAP is changed.
    /// @param caller The caller's address
    /// @param oldTwap Current twap address
    /// @param newTwap Updated twap address
    event TwapUpdated(address indexed caller, address oldTwap, address newTwap);

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

    /// @notice Returns the aggregate price along with introspection information.
    /// @return val The price obtained.
    /// @return age The age of the price.
    /// @return status Details of the introspection of the read call.
    function readWithStatus()
        external
        view
        returns (uint, uint, StatusInfo memory);

    /// @notice Updates the agreement distance (%).
    /// @param agreementDistance The percentage under which Oracle prices must agree.
    function setAgreementDistance(uint agreementDistance) external;

    function setAcceptableAgeThreshold(uint acceptableAgeThreshold) external;

    /// @notice Updates the set of Oracles to query.
    /// @param oracles The set of oracle addresses to update. Will overwrite
    ///                existing oracles.
    function setOracles(address[] calldata oracles) external;

    /// @notice Sets the TWAP address for the TWAP tie-breaker.
    /// @param twap The address of the TWAP wrapper contract.
    function setTwap(address twap) external;
}
