// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracle} from "src/interfaces/IOracle.sol";

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";
import {IChainlinkAggregator} from "src/interfaces/_external/IChainlinkAggregator.sol";

contract OracleAggregator is IOracle {
    error CannotBeZero();
    error ZeroAddress();
    error ChainlinkStalePrice(uint256 clUpdatedAt, uint256 difference);
    error ReportedPriceIsZero(uint256 chainlinkValue, uint256 chronicleValue);

    // --- Auth ---
    mapping(address => uint256) public wards;
    function rely(address usr) external auth {
        wards[usr] = 1;
    }
    function deny(address usr) external auth {
        wards[usr] = 0;
    }
    modifier auth() {
        require(wards[msg.sender] == 1, "Oracle/not-authorized");
        _;
    }

    // --- Vars ---
    address public chronicle;
    address public chainlink;

    /// @dev The mean of the oracle prices. If there is any error in _valueSet()
    ///      from any partnered oracle, we return this value.
    uint256 private lastAgreedMeanPrice;
    uint256 public updatedAt;

    /// @dev Used as a staleness threshold. It does not prevent us from returning 
    ///      a price, but it will flag the "staleness" flag on valueRead().
    ///      Additionally, it is used to decide whether the value returned by
    ///      Chainlink is fresh enough [see poke()].
    uint256 public stalenessThresholdSec;

    struct CLData{
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        uint256 decimals;
    }
    CLData private chainlinkData;

    // --- Funcs ---
    constructor(address _chronicle, address _chainlink) {
        wards[msg.sender] = 1;
        if (_chronicle == address(0)) revert ZeroAddress();
        if (_chainlink == address(0)) revert ZeroAddress();
        chronicle = _chronicle;
        chainlink = _chainlink;
    }

    function read() external /*toll*/ view returns (uint256) {
        return lastAgreedMeanPrice;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (chainlinkData.roundId, int256(lastAgreedMeanPrice),
                chainlinkData.startedAt, chainlinkData.updatedAt, chainlinkData.answeredInRound);
    }

    function latestAnswer() external view returns (int256) {
        return int256(lastAgreedMeanPrice);
    }

    function valueRead() external view override(IOracle) returns (uint256 value, bool isStale) {
        value = lastAgreedMeanPrice;
        isStale = (block.timestamp - updatedAt) <= stalenessThresholdSec;
    }

    /// @dev Poking is required. On a successful poke a mean price is set along with
    ///      the update timestamp. On any reversion these values will NOT be set and
    ///      any request returned to consumers will be the last known "good" mean
    ///      price.
    function poke() external {
        // Query Chainlink oracle
        (chainlinkData.roundId,
         chainlinkData.answer,
         chainlinkData.startedAt,
         chainlinkData.updatedAt,
         chainlinkData.answeredInRound,
         chainlinkData.decimals) = _readOracle_Chainlink(chainlink);

        uint256 diff = block.timestamp - chainlinkData.updatedAt;
        if (!(diff <= stalenessThresholdSec)) {
            revert ChainlinkStalePrice(chainlinkData.updatedAt, diff);
        }

        // Query Chronicle oracle
        (uint256 cvalue, ) = _readOracle_Chronicle(chronicle);

        // Zero check
        if (chainlinkData.answer <= 0 || cvalue <= 0) {
            if (chainlinkData.answer == 0 && cvalue == 0) { // Both agree that price is zero
                lastAgreedMeanPrice = 0;
                updatedAt = block.timestamp;
                return;
            }
            revert ReportedPriceIsZero(uint256(chainlinkData.answer), cvalue);
        }

        // Properly decimalize Chainlink value
        uint256 value;
        if (chainlinkData.decimals == 18) {
            value = uint256(chainlinkData.answer);
        } else if (chainlinkData.decimals < 18) {
            value = uint256(chainlinkData.answer) * 10**(18-chainlinkData.decimals);
        } else if (chainlinkData.decimals > 18) {
            value = uint256(chainlinkData.answer) / 10**(chainlinkData.decimals - 18);
        }

        // Produce the mean
        lastAgreedMeanPrice = (value + cvalue) / 2;
        updatedAt = block.timestamp;
    }

    function setStalenessThreshold(uint256 thresholdInSec) external auth {
        if (thresholdInSec == 0) revert CannotBeZero();
        stalenessThresholdSec = thresholdInSec;
    }

    // -- readOracle Implementations --

    function _readOracle_Chainlink(address orcl) internal view returns
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 _updatedAt, uint80 answeredInRound, uint256 decimals) {
        decimals = uint256(IChainlinkAggregator(orcl).decimals());
        (roundId, answer, startedAt, _updatedAt, answeredInRound) = IChainlinkAggregator(orcl).latestRoundData();
    }

    function _readOracle_Chronicle(address orcl) internal view returns (uint256, bool) {
        try IChronicle(orcl).read() returns (uint256 value) {
            return (value, true);
        } catch {
            return (0, false);
        }
    }
}
