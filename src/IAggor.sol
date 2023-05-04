// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// @todo Move IChronicle to chronicle-std.
import {IChronicle} from "./interfaces/_external/IChronicle.sol";

interface IAggor is IChronicle {
    error OracleReadFailed(address oracle);

    event StalenessThresholdUpdated(
        address indexed caller,
        uint oldStalenessThreshold,
        uint newStalenessThreshold
    );

    event ChainlinkValueStale(uint age, uint timestamp);
    event ChainlinkValueNegative(int value);
    event ChainlinkValueZero();

    function chronicle() external view returns (address);
    function chainlink() external view returns (address);

    function poke() external;

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

    function latestAnswer() external view returns (int);

    function stalenessThreshold() external view returns (uint);
    function setStalenessThreshold(uint stalenessThreshold) external;
}
