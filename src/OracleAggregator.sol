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

    // The mean of the oracle prices. If there is any error in _valueSet() from
    // any partnered oracle, we return this value
    uint256 public lastAgreedMeanPrice;
    uint256 public updatedAt;

    //
    uint256 public stalenessThresholdSec;

    struct CLData{
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        uint256 decimals;
    }
    CLData public chainLinkData;

    // --- Funcs ---
    constructor(address _chronicle, address _chainlink) {
        wards[msg.sender] = 1;
        if (_chronicle == address(0)) revert ZeroAddress();
        if (_chainlink == address(0)) revert ZeroAddress();
        chronicle = _chronicle;
        chainlink = _chainlink;
    }

    function read() external /*toll*/ view returns (uint256 value) {
        (value,) = this.valueRead();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (chainLinkData.roundId, int256(lastAgreedMeanPrice),
                chainLinkData.startedAt, chainLinkData.updatedAt, chainLinkData.answeredInRound);
    }

    function latestAnswer() external view returns (int256) {
        return int256(lastAgreedMeanPrice);
    }

    function valueRead() external view override(IOracle) returns (uint256 value, bool isStale) {
        value = lastAgreedMeanPrice;
        isStale = (block.timestamp - updatedAt) <= stalenessThresholdSec;
    }

    function poke() external {
        // Query Chainlink oracle
        (chainLinkData.roundId,
         chainLinkData.answer,
         chainLinkData.startedAt,
         chainLinkData.updatedAt,
         chainLinkData.answeredInRound,
         chainLinkData.decimals) = _readOracle_Chainlink(chainlink);

        uint256 diff = block.timestamp - chainLinkData.updatedAt;
        if (!(diff <= stalenessThresholdSec)) {
            revert ChainlinkStalePrice(chainLinkData.updatedAt, diff);
        }

        // Query Chronicle oracle
        (uint256 cvalue, ) = _readOracle_Chronicle(chronicle);

        // Zero check
        if (chainLinkData.answer <= 0 || cvalue <= 0) {
            if (chainLinkData.answer == 0 && cvalue == 0) {
                lastAgreedMeanPrice = 0;
            }
            revert ReportedPriceIsZero(uint256(chainLinkData.answer), cvalue);
        }

        // Properly decimalize Chainlink value
        uint256 value;
        if (chainLinkData.decimals == 18) {
            value = uint256(chainLinkData.answer);
        } else if (chainLinkData.decimals < 18) {
            value = uint256(chainLinkData.answer) * 10**(18-chainLinkData.decimals);
        } else if (chainLinkData.decimals > 18) {
            value = uint256(chainLinkData.answer) / 10**(chainLinkData.decimals - 18);
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
