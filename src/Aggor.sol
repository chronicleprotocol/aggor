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
    address public immutable uniPool;

    /// @inheritdoc IAggor
    address public immutable uniBasePair;

    /// @inheritdoc IAggor
    address public immutable uniQuotePair;

    /// @inheritdoc IAggor
    uint8 public immutable uniBaseDec;

    /// @inheritdoc IAggor
    uint8 public immutable uniQuoteDec;

    /// @inheritdoc IAggor
    uint32 public uniSecondsAgo;

    /// @inheritdoc IAggor
    uint32 public stalenessThreshold;

    /// @inheritdoc IAggor
    uint16 public spread;

    /// @inheritdoc IAggor
    bool public uniswapSelected;

    // This is the last agreed upon mean price.
    uint128 private _val;
    uint32 private _age;

    /// @notice You only get once chance per deploy to setup Uniswap. If it
    ///         will not be used, just pass in address(0) for uniPool_.
    /// @param initialAuthed Address to be initially auth'ed
    /// @param chronicle_ Address of Chronicle oracle
    /// @param chainlink_ Address of Chainlink oracle
    /// @param uniPool_ Address of Uniswap oracle (optional)
    /// @param uniUseToken0AsBase If true, selects Pool.token0 as base pair, if not,
    //         it uses Pool.token1 as the base pair.
    constructor(
        address initialAuthed,
        address chronicle_,
        address chainlink_,
        address uniPool_,
        bool uniUseToken0AsBase
    ) Auth(initialAuthed) {
        require(chronicle_ != address(0));
        require(chainlink_ != address(0));

        chronicle = chronicle_;
        chainlink = chainlink_;

        // Note that IChronicle::wat() is constant and save to cache.
        wat = IChronicle(chronicle_).wat();

        // Optionally initialize Uniswap.
        address uniPoolInitializer;
        address uniBasePairInitializer;
        address uniQuotePairInitializer;
        uint8 uniBaseDecInitializer;
        uint8 uniQuoteDecInitializer;

        if (uniPool_ != address(0)) {
            uniPoolInitializer = uniPool_;

            if (uniUseToken0AsBase) {
                uniBasePairInitializer =
                    IUniswapV3PoolImmutables(uniPoolInitializer).token0();
                uniQuotePairInitializer =
                    IUniswapV3PoolImmutables(uniPoolInitializer).token1();
            } else {
                uniBasePairInitializer =
                    IUniswapV3PoolImmutables(uniPoolInitializer).token1();
                uniQuotePairInitializer =
                    IUniswapV3PoolImmutables(uniPoolInitializer).token0();
            }

            uniBaseDecInitializer = IERC20(uniBasePairInitializer).decimals();
            uniQuoteDecInitializer = IERC20(uniQuotePairInitializer).decimals();
        }

        uniPool = uniPoolInitializer;
        uniBasePair = uniBasePairInitializer;
        uniQuotePair = uniQuotePairInitializer;
        uniBaseDec = uniBaseDecInitializer;
        uniQuoteDec = uniQuoteDecInitializer;

        // Default config values
        _setStalenessThreshold(1 days);
        _setSpread(500); // 5%

        if (uniPool != address(0)) {
            _setUniSecondsAgo(5 minutes);
        }
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
        // assert(valChronicle != 0);
        // assert(valChronicle <= type(uint128).max);

        // Read second oracle, either Chainlink or Uniswap TWAP.
        uint valOther;
        if (!uniswapSelected) {
            // Read Chainlink.
            (ok, valOther) = _tryReadChainlink();
            if (!ok) {
                revert OracleReadFailed(chainlink);
            }
        } else {
            // assert(uniPool != address(0));

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

        if (diff > spread) {
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
    function setStalenessThreshold(uint32 stalenessThreshold_) external auth {
        _setStalenessThreshold(stalenessThreshold_);
    }

    function _setStalenessThreshold(uint32 stalenessThreshold_) internal {
        require(stalenessThreshold_ != 0);

        if (stalenessThreshold != stalenessThreshold_) {
            emit StalenessThresholdUpdated(
                msg.sender, stalenessThreshold, stalenessThreshold_
            );
            stalenessThreshold = stalenessThreshold_;
        }
    }

    /// @inheritdoc IAggor
    function setSpread(uint16 spread_) external auth {
        _setSpread(spread_);
    }

    function _setSpread(uint16 spread_) internal {
        require(spread_ <= _pscale);

        if (spread != spread_) {
            emit SpreadUpdated(msg.sender, spread, spread_);
            spread = spread_;
        }
    }

    /// @inheritdoc IAggor
    function useUniswap(bool selected) external auth {
        // Uniswap pool must be configured
        require(uniPool != address(0));

        // Revert unless there is something to change
        require(uniswapSelected != selected);

        emit UniswapSelectedUpdated({
            caller: msg.sender,
            oldValue: uniswapSelected,
            newValue: selected
        });

        uniswapSelected = selected;
    }

    /// @inheritdoc IAggor
    function setUniSecondsAgo(uint32 uniSecondsAgo_) external auth {
        _setUniSecondsAgo(uniSecondsAgo_);
    }

    function _setUniSecondsAgo(uint32 uniSecondsAgo_) internal {
        // Uniswap is optional, make sure it's configured
        require(uniPool != address(0));
        require(uniSecondsAgo_ >= minUniSecondsAgo);

        if (uniSecondsAgo != uniSecondsAgo_) {
            emit UniswapSecondsAgoUpdated(
                msg.sender, uniSecondsAgo, uniSecondsAgo_
            );
            uniSecondsAgo = uniSecondsAgo_;
        }

        // Ensure that the pool works within the desired "lookback" period.
        (bool ok,) = _tryReadUniswap();
        require(ok);
    }

    // -- Private Helpers --

    function _tryReadUniswap() internal view returns (bool, uint) {
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
            return (false, 0);
        }

        // Also fail if could cause overflow.
        if (val > type(uint128).max) {
            return (false, 0);
        }

        return (true, val);
    }

    function _tryReadChronicle() internal view returns (bool, uint) {
        bool ok;
        uint val;
        uint age;
        (ok, val, age) = IChronicle(chronicle).tryReadWithAge();
        // assert(!ok || val != 0);

        // Fail if value stale.
        uint diff = block.timestamp - age;
        if (diff > stalenessThreshold) {
            return (false, 0);
        }

        return (ok, val);
    }

    function _tryReadChainlink() internal view returns (bool, uint) {
        int answer;
        uint updatedAt;
        (, answer,, updatedAt,) =
            IChainlinkAggregatorV3(chainlink).latestRoundData();

        // Fail if value stale.
        uint diff = block.timestamp - updatedAt;
        if (diff > stalenessThreshold) {
            return (false, 0);
        }

        // Fail if value negative.
        if (answer < 0) {
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
