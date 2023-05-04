// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IAggor} from "./IAggor.sol";

// @todo Move IChronicle to chronicle-std.
import {IChronicle} from "./interfaces/_external/IChronicle.sol";
import {IChainlinkAggregatorV3} from
    "./interfaces/_external/IChainlinkAggregatorV3.sol";

contract Aggor is IAggor, Auth, Toll {
    address public chronicle;
    address public chainlink;

    uint public stalenessThreshold = 1 days;

    uint128 private _val;
    uint32 private _age;

    constructor(address chronicle_, address chainlink_) {
        require(chronicle_ != address(0));
        require(chainlink_ != address(0));

        chronicle = chronicle_;
        chainlink = chainlink_;
    }

    function poke() external {
        bool ok;

        // Read chronicle.
        uint valChronicle;
        (ok, valChronicle) = _tryReadChronicle();
        if (!ok) {
            revert OracleReadFailed(chronicle);
        }
        assert(valChronicle != 0);
        assert(valChronicle <= type(uint128).max);

        // Read chainlink.
        uint valChainlink;
        (ok, valChainlink) = _tryReadChainlink();
        if (!ok) {
            revert OracleReadFailed(chainlink);
        }
        assert(valChainlink <= type(uint128).max);

        // Compute mean.
        // Unsafe ok because both arguments are <= type(uint128).max.
        uint mean = _unsafeMean(valChainlink, valChronicle);
        assert(mean <= type(uint128).max);

        // Store mean as val and set its age to now.
        _val = uint128(mean);
        _age = uint32(block.timestamp);
    }

    // -- Read Functionality --

    // -- IChronicle

    function read() external view toll returns (uint) {
        require(_val != 0);
        return _val;
    }

    function tryRead() external view toll returns (bool, uint) {
        return (_val != 0, _val);
    }

    // -- IChainlinkAggregatorV3

    function latestRoundData()
        external
        view
        toll
        returns (uint80, int, uint, uint, uint80)
    {
        return (0, _toInt(_val), 0, _age, 0);
    }

    /// @custom:deprecated See https://docs.chain.link/data-feeds/api-reference/#latestanswer.
    function latestAnswer() external view toll returns (int) {
        return _toInt(_val);
    }

    // -- Auth'ed Functionality --

    function setStalenessThreshold(uint stalenessThreshold_) external auth {
        require(stalenessThreshold_ != 0);

        if (stalenessThreshold != stalenessThreshold_) {
            emit StalenessThresholdUpdated(
                msg.sender, stalenessThreshold, stalenessThreshold_
            );
            stalenessThreshold = stalenessThreshold_;
        }
    }

    // -- Private Helpers --

    function _tryReadChronicle() private view returns (bool, uint) {
        return IChronicle(chronicle).tryRead();
    }

    function _tryReadChainlink() private returns (bool, uint) {
        int answer;
        uint updatedAt;
        (, answer,, updatedAt,) =
            IChainlinkAggregatorV3(chainlink).latestRoundData();

        // Fail if value stale.
        uint diff = block.timestamp - updatedAt;
        if (diff > stalenessThreshold) {
            emit ChainlinkValueStale(updatedAt, block.timestamp);
            return (false, 0);
        }

        // Fail if value negative.
        if (answer < 0) {
            emit ChainlinkValueNegative(answer);
            return (false, 0);
        }

        // Adjust decimals, if necessary.
        uint val;
        uint decimals = IChainlinkAggregatorV3(chainlink).decimals();
        if (decimals == 18) {
            val = uint(answer);
        } else if (decimals < 18) {
            val = uint(answer) * (10 ** (18 - decimals));
        } else {
            val = uint(answer) / (10 ** (decimals - 18));
        }

        // Fail if value is zero.
        if (val == 0) {
            emit ChainlinkValueZero();
            return (false, 0);
        }

        // Otherwise value is ok.
        return (true, val);
    }

    function _toInt(uint128 val) private pure returns (int) {
        // Note that int(type(uint128).max) == type(uint128).max.
        return int(uint(val));
    }

    function _unsafeMean(uint a, uint b) private pure returns (uint) {
        uint mean;
        unchecked {
            // Note that >> 1 equals a division by 2.
            mean = (a + b) >> 1;
        }
        return mean;
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}
