// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracle} from "src/interfaces/IOracle.sol";

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";
import {IChainlinkAggregator} from "src/interfaces/_external/IChainlinkAggregator.sol";

error UnknownOracleKind();
error CannotBeZero();
error ZeroAddress();

contract OracleAggregator is IOracle {
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

    function read() external /*toll*/ returns (uint256 value) {
        (value,) = this.valueRead();
    }

    function latestRoundData() external returns (uint80, int256, uint256, uint256, uint80) {
        (uint256 value,, CLData memory cld) = _valueRead();
        return (cld.roundId, int256(value), cld.startedAt, cld.updatedAt, cld.answeredInRound);
    }

    function latestAnswer() external returns (int256) {
        (uint256 value,) = this.valueRead();
        return int256(value);
    }

    address public chronicle;
    address public chainlink;
    constructor(address _chronicle, address _chainlink) {
        wards[msg.sender] = 1;
        if (_chronicle == address(0)) revert ZeroAddress();
        if (_chainlink == address(0)) revert ZeroAddress();
        chronicle = _chronicle;
        chainlink = _chainlink;
    }

    // The mean of the oracle prices. If there is any error in valueRead() from
    // the partnered oracles, we return this value
    uint256 public lastKnownMeanPrice;

    struct CLData{
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
        uint256 decimals;
    }

    function valueRead() external override(IOracle) returns (uint256, bool) {
        (uint256 val, bool ok,) = _valueRead();
        return (val, ok);
    }

    function _valueRead() internal returns (uint256, bool, CLData memory) {
        // Query Chainlink oracle
        CLData memory cld;
        (cld.roundId,
         cld.answer,
         cld.startedAt,
         cld.updatedAt,
         cld.answeredInRound,
         cld.decimals) = _readOracle_Chainlink(chainlink);

        uint256 diff = block.timestamp - cld.updatedAt;
        if (!(diff <= chainlinkStalenessThresholdSec)) {
            //emit ChainLinkStalePrice
            return (lastKnownMeanPrice, false, cld);
        }

        // Query Chronicle oracle
        (uint256 cvalue, ) = _readOracle_Chronicle(chronicle);

        // Zero check
        if (cld.answer <= 0 || cvalue <= 0) {
            if (cld.answer == 0 && cvalue == 0) {
                lastKnownMeanPrice = 0;
                return (lastKnownMeanPrice, true, cld); // TODO both agree price is zero... ?
            }
            // emit ReportedPriceIsZero
            return (lastKnownMeanPrice, false, cld);
        }

        // Properly decimalize Chainlink value
        uint256 value;
        if (cld.decimals == 18) {
            value = uint256(cld.answer);
        } else if (cld.decimals < 18) {
            value = uint256(cld.answer) * 10**(18-cld.decimals);
        } else if (cld.decimals > 18) {
            value = uint256(cld.answer) / 10**(cld.decimals - 18);
        }

        // Produce the mean
        lastKnownMeanPrice = (value + cvalue) / 2;
        return (lastKnownMeanPrice, true, cld);
    }

    uint256 public chainlinkStalenessThresholdSec;
    function setChainlinkStalenessThreshold(uint256 thresholdInSec) external auth {
        if (thresholdInSec == 0) revert CannotBeZero();
        chainlinkStalenessThresholdSec = thresholdInSec;
    }

    // -- readOracle Implementations --

    function _readOracle_Chainlink(address orcl) internal view returns
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound, uint256 decimals) {
        decimals = uint256(IChainlinkAggregator(orcl).decimals());
        (roundId, answer, startedAt, updatedAt, answeredInRound) = IChainlinkAggregator(orcl).latestRoundData();
        //TODO can this revert, if so... try ^
    }

    function _readOracle_Chronicle(address orcl) internal view returns (uint256, bool) {
        try IChronicle(orcl).read() returns (uint256 value) {
            return (value, true);
        } catch {
            return (0, false);
        }
    }
}
