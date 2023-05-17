// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IAggor} from "./IAggor.sol";

import {IChainlinkAggregatorV3} from
    "./interfaces/_external/IChainlinkAggregatorV3.sol";

/**
 * @title Aggor
 * @custom:version 0.1.0
 *
 * @notice Aggor combines oracle values from multiple providers into a single
 *         value
 */
contract Aggor is IAggor, Auth, Toll {
    /// @dev Percentage scale is in basis points (BPS).
    uint internal constant _pscale = 10_000;

    /// @inheritdoc IAggor
    uint8 public constant decimals = 18;

    /// @inheritdoc IChronicle
    bytes32 public immutable wat;

    /// @inheritdoc IAggor
    address public immutable chronicle;

    /// @inheritdoc IAggor
    address public immutable chainlink;

    /// @inheritdoc IAggor
    uint public stalenessThreshold;

    /// @inheritdoc IAggor
    uint public spread;

    // This is the last agreed upon mean price.
    uint128 private _val;
    uint32 private _age;

    constructor(address chronicle_, address chainlink_) {
        require(chronicle_ != address(0));
        require(chainlink_ != address(0));

        chronicle = chronicle_;
        chainlink = chainlink_;

        // Note that IChronicle::wat() is a constant and save to cache.
        wat = IChronicle(chronicle_).wat();

        setStalenessThreshold(1 days);
        setSpread(500);
    }

    /// @inheritdoc IAggor
    function poke() external {
        _poke();
    }

    /// @dev Optimized function selector: 0x00000000.
    ///      Note that this function is _not_ defined via the IAggor interface
    ///      and one should _not_ depend on it.
    function poke_optimized_3923566589() external {
        _poke();
    }

    function _poke() internal {
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
        assert(valChainlink != 0);
        assert(valChainlink <= type(uint128).max);

        // Check for suspicious deviation between oracles. Whichever price is
        // nearest the previously agreed upon mean becomes _val.
        uint checkSpread = _pctdiff(valChronicle, valChainlink);
        if (checkSpread > 0 && checkSpread > spread) {
            _val = _distance(_val, valChronicle) < _distance(_val, valChainlink)
                ? uint128(valChronicle)
                : uint128(valChainlink);
            _age = uint32(block.timestamp);
            return;
        }

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

    /// @inheritdoc IChronicle
    function read() external view toll returns (uint) {
        require(_val != 0);
        return _val;
    }

    /// @inheritdoc IChronicle
    function tryRead() external view toll returns (bool, uint) {
        return (_val != 0, _val);
    }

    /// @inheritdoc IChronicle
    function readWithAge() external view toll returns (uint, uint) {
        require(_val != 0);
        return (_val, _age);
    }

    /// @inheritdoc IChronicle
    function tryReadWithAge() external view toll returns (bool, uint, uint) {
        return (_val != 0, _val, _age);
    }

    // -- IChainlinkAggregatorV3

    /// @inheritdoc IAggor
    function latestRoundData()
        external
        view
        virtual
        toll
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        )
    {
        roundId = 1;
        answer = _toInt(_val);
        assert(uint(answer) == uint(_val));
        startedAt = 0;
        updatedAt = _age;
        answeredInRound = roundId;
    }

    /// @inheritdoc IAggor
    function latestAnswer() external view toll returns (int) {
        return _toInt(_val);
    }

    // -- Auth'ed Functionality --

    /// @inheritdoc IAggor
    function setStalenessThreshold(uint stalenessThreshold_) public auth {
        require(stalenessThreshold_ != 0);

        if (stalenessThreshold != stalenessThreshold_) {
            emit StalenessThresholdUpdated(
                msg.sender, stalenessThreshold, stalenessThreshold_
            );
            stalenessThreshold = stalenessThreshold_;
        }
    }

    /// @inheritdoc IAggor
    function setSpread(uint spread_) public auth {
        require(spread_ <= _pscale);

        if (spread != spread_) {
            emit SpreadUpdated(msg.sender, spread, spread_);
            spread = spread_;
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
        uint decimals_ = IChainlinkAggregatorV3(chainlink).decimals();
        if (decimals_ == 18) {
            val = uint(answer);
        } else if (decimals_ < 18) {
            val = uint(answer) * (10 ** (18 - decimals_));
        } else {
            val = uint(answer) / (10 ** (decimals_ - 18));
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

    /// @dev Compute the percent difference of two numbers with a precision of
    ///      _pscale (99.99%).
    function _pctdiff(uint a, uint b) private pure returns (uint) {
        if (a == b) return 0;
        return a > b
            ? _pscale - (((b * 1e18) / a) * _pscale / 1e18)
            : _pscale - (((a * 1e18) / b) * _pscale / 1e18);
    }

    /// @dev Compute the numerical distance between two numbers. No overflow
    ///      worries here.
    function _distance(uint a, uint b) private pure returns (uint) {
        unchecked {
            return (a > b) ? a - b : b - a;
        }
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}
