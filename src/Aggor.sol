// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IUniswapV3PoolImmutables} from
    "uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolImmutables.sol";

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {LibCalc} from "./libs/LibCalc.sol";
import {LibUniswapOracles} from "./libs/LibUniswapOracles.sol";

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
    uint16 internal constant _pscale = 10_000;

    /// @inheritdoc IAggor
    uint32 public constant minUniSecondsAgo = 5 minutes;

    /// @inheritdoc IAggor
    uint8 public constant decimals = 18;

    /// @inheritdoc IChronicle
    bytes32 public immutable wat;

    /// @inheritdoc IAggor
    address public immutable chronicle;

    /// @inheritdoc IAggor
    address public immutable chainlink;

    /// @inheritdoc IAggor
    address public uniPool;

    /// @inheritdoc IAggor
    address public uniBasePair;

    /// @inheritdoc IAggor
    address public uniQuotePair;

    /// @inheritdoc IAggor
    uint8 public uniBaseDec;

    /// @inheritdoc IAggor
    uint8 public uniQuoteDec;

    /// @inheritdoc IAggor
    uint32 public uniSecondsAgo;

    /// @inheritdoc IAggor
    uint32 public stalenessThreshold;

    /// @inheritdoc IAggor
    uint16 public spread;

    /// @inheritdoc IAggor
    bool public paused;

    // This is the last agreed upon mean price.
    uint128 private _val;
    uint32 private _age;

    constructor(address chronicle_, address chainlink_) {
        require(chronicle_ != address(0));
        require(chainlink_ != address(0));

        chronicle = chronicle_;
        chainlink = chainlink_;

        // Note that IChronicle::wat() is constant and save to cache.
        wat = IChronicle(chronicle_).wat();

        setStalenessThreshold(1 days);
        setSpread(500); // 5%
        setUniSecondsAgo(5 minutes);
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
        if (paused) return;
        bool ok;

        // Read chronicle.
        uint valChronicle;
        (ok, valChronicle) = _tryReadChronicle();
        if (!ok) {
            revert OracleReadFailed(chronicle);
        }
        // assert(valChronicle != 0);
        // assert(valChronicle <= type(uint128).max);

        // Read second oracle, i.e. either Chainlink or Uniswap TWAP.
        uint valOther;
        if (uniPool == address(0)) {
            // Read Chainlink.
            (ok, valOther) = _tryReadChainlink();
            if (!ok) {
                revert OracleReadFailed(chainlink);
            }
        } else {
            // Read Uniswap.
            (ok, valOther) = _tryReadUniswap();
            if (!ok) {
                revert OracleReadFailed(uniPool);
            }
        }
        // assert(valOther != 0);
        // assert(valOther <= type(uint128).max);

        // Compute difference of oracle values.
        uint diff =
            LibCalc.pctDiff(uint128(valChronicle), uint128(valOther), _pscale);

        if (diff != 0 && diff > spread) {
            // If difference is bigger than acceptable spread, let _val be the
            // oracle's value with less difference to the current _val.
            // forgefmt: disable-next-item
            _val = LibCalc.distance(_val, valChronicle) < LibCalc.distance(_val, valOther)
                ? uint128(valChronicle)
                : uint128(valOther);
        } else {
            // If difference is within acceptable spread, let _val be the mean
            // of the oracles' values.
            // Note that unsafe computation is fine because both arguments are
            // less than or equal to type(uint128).max.
            _val = uint128(LibCalc.unsafeMean(valChronicle, valOther));
        }
        // assert(_val <= type(uint128).max);

        // Update _val's age to current timestamp.
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
        // assert(uint(answer) == uint(_val));
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
    function setStalenessThreshold(uint32 stalenessThreshold_) public auth {
        require(stalenessThreshold_ != 0);

        if (stalenessThreshold != stalenessThreshold_) {
            emit StalenessThresholdUpdated(
                msg.sender, stalenessThreshold, stalenessThreshold_
            );
            stalenessThreshold = stalenessThreshold_;
        }
    }

    /// @inheritdoc IAggor
    function setSpread(uint16 spread_) public auth {
        require(spread_ <= _pscale);

        if (spread != spread_) {
            emit SpreadUpdated(msg.sender, spread, spread_);
            spread = spread_;
        }
    }

    /// @inheritdoc IAggor
    function setUniswap(address uniPool_) public auth {
        if (uniPool == uniPool_) return;

        // Update Uniswap pool variable.
        emit UniswapUpdated(msg.sender, uniPool, uniPool_);
        uniPool = uniPool_;

        if (uniPool_ != address(0)) {
            // Set other Uniswap variables.
            uniBasePair = IUniswapV3PoolImmutables(uniPool).token0();
            uniQuotePair = IUniswapV3PoolImmutables(uniPool).token1();
            uniBaseDec = IERC20(uniBasePair).decimals();
            uniQuoteDec = IERC20(uniQuotePair).decimals();
        } else {
            // Delete other Uniswap variables.
            delete uniBasePair;
            delete uniQuotePair;
            delete uniBaseDec;
            delete uniQuoteDec;
        }
    }

    /// @inheritdoc IAggor
    function setUniSecondsAgo(uint32 uniSecondsAgo_) public auth {
        require(uniSecondsAgo_ >= minUniSecondsAgo);

        if (uniSecondsAgo != uniSecondsAgo_) {
            emit UniswapSecondsAgoUpdated(
                msg.sender, uniSecondsAgo, uniSecondsAgo_
            );
            uniSecondsAgo = uniSecondsAgo_;
        }
    }

    // -- Private Helpers --

    function _tryReadUniswap() internal returns (bool, uint) {
        // assert(uniPool != address(0));

        uint val = LibUniswapOracles.readOracle(
            uniPool, uniBasePair, uniQuotePair, uniBaseDec, uniSecondsAgo
        );

        // We always scale to 'decimals', up OR down.
        if (uniQuoteDec != decimals) {
            val = LibCalc.scale(val, uniQuoteDec, decimals);
        }

        // Fail if value is zero.
        if (val == 0) {
            emit UniswapValueZero();
            return (false, 0);
        }

        return (true, val);
    }

    function _tryReadChronicle() internal returns (bool, uint) {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = IChronicle(chronicle).tryReadWithAge();
        // assert(!ok || val != 0);

        // Fail if value stale.
        uint diff = block.timestamp - age;
        if (diff > stalenessThreshold) {
            emit ChronicleValueStale(age, block.timestamp);
            return (false, 0);
        }

        return (ok, val);
    }

    function _tryReadChainlink() internal returns (bool, uint) {
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
        uint val = uint(answer);
        uint decimals_ = IChainlinkAggregatorV3(chainlink).decimals();
        if (decimals_ != decimals) {
            val = LibCalc.scale(val, decimals_, decimals);
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

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}
