// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {IChainlinkAggregatorV3} from
    "./interfaces/_external/IChainlinkAggregatorV3.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Pool} from
    "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IAggor} from "./IAggor.sol";

import {LibUniswapOracles} from "./libs/LibUniswapOracles.sol";
import {LibMedian} from "./libs/LibMedian.sol";

/**
 * @title Aggor
 *
 * @notice Aggor combines oracle values from multiple providers into a single
 *         value
 */
contract Aggor is IAggor, Auth, Toll {
    using LibUniswapOracles for address;

    // -- Internal Constants --

    /// @dev The maximum number of decimals for Uniswap's base asset supported.
    uint internal constant _MAX_UNISWAP_BASE_DECIMALS = 38;

    uint8 internal constant _DECIMALS_CHRONICLE = 18;

    // -- Immutable Configurations --

    // -- Chainlink Compatibility

    /// @inheritdoc IAggor
    uint8 public constant decimals = 8;

    // -- Oracles

    /// @inheritdoc IAggor
    address public chronicle;
    /// @inheritdoc IAggor
    address public chainlink;

    // -- Twap

    /// @inheritdoc IAggor
    address public uniswapPool;
    /// @inheritdoc IAggor
    address public uniswapBaseToken;
    /// @inheritdoc IAggor
    address public uniswapQuoteToken;
    /// @inheritdoc IAggor
    uint8 public uniswapBaseTokenDecimals;
    /// @inheritdoc IAggor
    uint32 public uniswapLookback;

    // -- Mutable Configurations --

    /// @inheritdoc IAggor
    uint128 public agreementDistance;
    /// @inheritdoc IAggor
    uint32 public ageThreshold;

    // -- Constructor --

    constructor(
        address initialAuthed,
        address chronicle_,
        address chainlink_,
        address uniswapPool_,
        address uniswapBaseToken_,
        address uniswapQuoteToken_,
        uint8 uniswapBaseTokenDecimals_,
        uint32 uniswapLookback_,
        uint128 agreementDistance_,
        uint32 ageThreshold_
    ) Auth(initialAuthed) {
        // Verify twap config arguments.
        _verifyTwapConfig(
            uniswapPool_,
            uniswapBaseToken_,
            uniswapQuoteToken_,
            uniswapBaseTokenDecimals_,
            uniswapLookback_
        );

        // Set immutables.
        chronicle = chronicle_;
        chainlink = chainlink_;
        uniswapPool = uniswapPool_;
        uniswapBaseToken = uniswapBaseToken_;
        uniswapQuoteToken = uniswapQuoteToken_;
        uniswapBaseTokenDecimals = uniswapBaseTokenDecimals_;
        uniswapLookback = uniswapLookback_;

        // Set configurations.
        _setAgreementDistance(agreementDistance_);
        _setAgeThreshold(ageThreshold_);
    }

    function _verifyTwapConfig(
        address uniswapPool_,
        address uniswapBaseToken_,
        address uniswapQuoteToken_,
        uint8 uniswapBaseTokenDecimals_,
        uint32 uniswapLookback_
    ) internal view {
        require(uniswapPool_ != address(0));

        address token0 = IUniswapV3Pool(uniswapPool_).token0();
        address token1 = IUniswapV3Pool(uniswapPool_).token1();

        // Verify base and quote tokens.
        require(uniswapBaseToken_ != uniswapQuoteToken_);
        require(uniswapBaseToken_ == token0 || uniswapBaseToken_ == token1);
        require(uniswapQuoteToken_ == token0 || uniswapQuoteToken_ == token1);

        // Verify base token's decimals.
        require(
            uniswapBaseTokenDecimals_ == IERC20(uniswapBaseToken_).decimals()
        );
        require(uniswapBaseTokenDecimals_ <= _MAX_UNISWAP_BASE_DECIMALS);

        // Verify TWAP is initialized.
        // Specifically, verify that the TWAP's oldest observation is older
        // then the uniswapLookback argument.
        uint32 oldestObservation = uniswapPool_.getOldestObservationSecondsAgo();
        require(oldestObservation > uniswapLookback_);
    }

    // -- Read Functionality --

    /// @dev Returns Aggor's derived value, timestamp and status information.
    ///
    /// @dev Note that the value's age is always block.timestamp except if the
    ///      value itself is invalid.
    function _read() internal view returns (uint128, uint, Status memory) {
        // Read chronicle and chainlink oracles.
        (bool ok_chr, uint128 val_chr) = _readChronicle();
        (bool ok_chl, uint128 val_chl) = _readChainlink();

        if (ok_chr && ok_chl) {
            // If both oracles ok and in agreement distance, return their median.
            if (_inAgreementDistance(val_chr, val_chl)) {
                return (
                    LibMedian.median(val_chr, val_chl),
                    block.timestamp,
                    Status({path: 2, goodOracleCtr: 2})
                );
            }

            // If both oracles ok but not in agreement distance, derive value
            // using TWAP as tie breaker.
            (bool ok_twap, uint128 val_twap) = _readTwap();
            if (ok_twap) {
                uint128 val = LibMedian.median(val_chr, val_chl, val_twap);
                return
                    (val, block.timestamp, Status({path: 3, goodOracleCtr: 2}));
            }

            // Otherwise not possible to decide which oracle is ok.
        } else if (ok_chr) {
            // If only chronicle ok, use chronicle's value.
            return
                (val_chr, block.timestamp, Status({path: 4, goodOracleCtr: 1}));
        } else if (ok_chl) {
            // If only chainlink ok, use chainlink's value.
            return
                (val_chl, block.timestamp, Status({path: 4, goodOracleCtr: 1}));
        }

        // If no oracle ok use TWAP.
        (bool ok, uint128 twap) = _readTwap();
        if (ok) {
            return (twap, block.timestamp, Status({path: 5, goodOracleCtr: 0}));
        }

        // Otherwise no value derivation possible.
        return (0, 0, Status({path: 6, goodOracleCtr: 0}));
    }

    /// @dev Reads the chronicle oracle.
    ///
    /// @dev Note that while chronicle uses 18 decimals, the returned value is
    ///      already scaled to `decimals`.
    ///
    /// @return bool Whether oracle is ok.
    /// @return uint128 The oracle's val.
    function _readChronicle() internal view returns (bool, uint128) {
        (bool ok, uint val, uint age) = IChronicle(chronicle).tryReadWithAge();
        // assert(val <= type(uint128).max);
        // assert(!ok || val != 0); // ok -> val != 0
        // assert(age <= block.timestamp);

        // Fail if not ok or value stale.
        if (!ok || age + ageThreshold < block.timestamp) {
            return (false, 0);
        }

        // Scale value down from chronicle decimals to aggor decimals.
        // assert(_DECIMALS_CHRONICLES >= decimals).
        val /= 10 ** (_DECIMALS_CHRONICLE - decimals);

        return (true, uint128(val));
    }

    /// @dev Reads the chainlink oracle.
    ///
    /// @return bool Whether oracle is ok.
    /// @return uint128 The oracle's val.
    function _readChainlink() internal view returns (bool, uint128) {
        // forgefmt: disable-next-item
        (
            /*uint80 roundId*/,
            int answer,
            /*uint startedAt*/,
            uint updatedAt,
            /*uint80 answeredInRound*/
        ) = IChainlinkAggregatorV3(chainlink).latestRoundData();
        // assert(updatedAt <= block.timestamp);

        // Fail if answer not in [1, type(uint128).max] or answer stale.
        if (
            (answer <= 0 || uint(answer) > uint(type(uint128).max))
                || updatedAt + ageThreshold < block.timestamp
        ) {
            return (false, 0);
        }

        // Otherwise ok.
        return (true, uint128(uint(answer)));
    }

    /// @dev Reads the twap oracle.
    ///
    /// @return bool Whether twap is ok.
    /// @return uint128 The twap's val.
    function _readTwap() internal view returns (bool, uint128) {
        // Read twap.
        uint twap = uniswapPool.readOracle(
            uniswapBaseToken,
            uniswapQuoteToken,
            uniswapBaseTokenDecimals,
            uniswapLookback
        );

        if (twap <= type(uint128).max) {
            return (true, uint128(twap));
        } else {
            return (false, 0);
        }
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
        (uint128 val, uint age, /*status*/ ) = _read();

        roundId = 1;
        answer = int(uint(val));
        startedAt = 0;
        updatedAt = age;
        answeredInRound = 1; // = roundId
    }

    /// @inheritdoc IAggor
    function latestAnswer() external view toll returns (int) {
        (uint128 val, /*age*/, /*status*/ ) = _read();

        return int(uint(val));
    }

    // -- IAggor

    /// @inheritdoc IAggor
    function readWithStatus()
        external
        view
        toll
        returns (uint, uint, Status memory)
    {
        return _read();
    }

    // -- Auth'ed Functionality --

    /// @inheritdoc IAggor
    function setAgreementDistance(uint128 agreementDistance_) external auth {
        _setAgreementDistance(agreementDistance_);
    }

    function _setAgreementDistance(uint128 agreementDistance_) internal {
        require(agreementDistance_ != 0);
        require(agreementDistance_ <= 1e18);

        if (agreementDistance != agreementDistance_) {
            emit AgreementDistanceUpdated(
                msg.sender, agreementDistance, agreementDistance_
            );
            agreementDistance = agreementDistance_;
        }
    }

    /// @inheritdoc IAggor
    function setAgeThreshold(uint32 ageThreshold_) external auth {
        _setAgeThreshold(ageThreshold_);
    }

    function _setAgeThreshold(uint32 ageThreshold_) internal {
        require(ageThreshold_ != 0);

        if (ageThreshold != ageThreshold_) {
            emit AcceptableAgeThresholdUpdated(
                msg.sender, ageThreshold, ageThreshold_
            );
            ageThreshold = ageThreshold_;
        }
    }

    // -- Internal Helpers --

    function _inAgreementDistance(uint128 a, uint128 b)
        internal
        view
        returns (bool)
    {
        // Compute %-difference in WAD.
        uint diff = a > b
            ? 1e18 - uint(b) * 1e18 / uint(a)
            : 1e18 - uint(a) * 1e18 / uint(b);

        // And return whether %-difference inside acceptable agreement distance.
        return diff <= agreementDistance;
    }

    // -- Overridden Toll Functions --

    /// @dev Defines authorization for IToll's authenticated functions.
    function toll_auth() internal override(Toll) auth {}
}

/**
 * @dev Contract overwrite to deploy contract instances with specific naming.
 *
 *      For more info, see docs/Deployment.md.
 */
contract Aggor_BASE_QUOTE_COUNTER is Aggor {
    // @todo   ^^^^ ^^^^^ ^^^^^^^ Adjust name of Aggor instance
    constructor(
        address initialAuthed,
        address chronicle_,
        address chainlink_,
        address uniswapPool_,
        address uniswapBaseToken_,
        address uniswapQuoteToken_,
        uint8 uniswapBaseDec_,
        uint32 uniswapLookback_,
        uint128 agreementDistance_,
        uint32 ageThreshold_
    )
        Aggor(
            initialAuthed,
            chronicle_,
            chainlink_,
            uniswapPool_,
            uniswapBaseToken_,
            uniswapQuoteToken_,
            uniswapBaseDec_,
            uniswapLookback_,
            agreementDistance_,
            ageThreshold_
        )
    {}
}
