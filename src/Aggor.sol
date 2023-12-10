// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {IChainlinkAggregatorV3} from
    "./interfaces/_external/IChainlinkAggregatorV3.sol";

import {IAggor} from "./IAggor.sol";

import {LibUniswapOracles} from "./libs/LibUniswapOracles.sol";

/**
 * @title Aggor
 *
 * @notice Aggor combines oracle values from multiple providers into a single
 *         value
 */
contract Aggor is IAggor, Auth, Toll {
    using LibUniswapOracles for address;

    // -- Internal Constants --

    uint16 internal constant _BPS = 10_000;

    uint8 internal constant _DECIMALS_CHRONICLE = 18;
    uint8 internal constant _DECIMALS_CHAINLINK = 8;

    // -- Immutable Configurations --

    // -- Chainlink Compatibility

    /// @inheritdoc IAggor
    uint8 public constant decimals = _DECIMALS_CHAINLINK;

    // -- Pegged Asset Mode

    /// @inheritdoc IAggor
    bool public immutable isPeggedAsset;
    /// @inheritdoc IAggor
    uint128 public immutable peggedPrice;

    // -- Oracles

    /// @inheritdoc IAggor
    address public immutable chronicle;
    /// @inheritdoc IAggor
    address public immutable chainlink;

    // -- Twap

    /// @inheritdoc IAggor
    address public immutable uniswapPool;
    /// @inheritdoc IAggor
    address public immutable uniswapBaseToken;
    /// @inheritdoc IAggor
    address public immutable uniswapQuoteToken;
    /// @inheritdoc IAggor
    uint8 public immutable uniswapBaseTokenDecimals;
    /// @inheritdoc IAggor
    uint32 public immutable uniswapLookback;

    // -- Mutable Configurations --

    /// @inheritdoc IAggor
    uint16 public agreementDistance;
    /// @inheritdoc IAggor
    uint32 public ageThreshold;

    // -- Constructor --

    constructor(
        address initialAuthed,
        bool isPeggedAsset_,
        uint128 peggedPrice_,
        address chronicle_,
        address chainlink_,
        address uniswapPool_,
        address uniswapBaseToken_,
        address uniswapQuoteToken_,
        uint8 uniswapBaseTokenDecimals_,
        uint32 uniswapLookback_,
        uint16 agreementDistance_,
        uint32 ageThreshold_
    ) Auth(initialAuthed) {
        // Set immutables.
        isPeggedAsset = isPeggedAsset_;
        peggedPrice = peggedPrice_;
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

    // -- Read Functionality --

    // Note that age is always block.timestamp.
    // Spark does not read age anyway.
    function _read() internal view returns (uint128, uint, Status memory) {
        // Read chronicle and chainlink oracles.
        (bool ok_chr, uint128 val_chr) = _readChronicle();
        (bool ok_chl, uint128 val_chl) = _readChainlink();

        // Dispatch following cases:
        // - Both oracles ok
        // - Only chronicle ok
        // - Only chainlink ok
        if (ok_chr && ok_chl) {
            // If both oracles ok and in agreement distance, return their median.
            if (inAgreementDistance(val_chr, val_chl)) {
                return (
                    median(val_chr, val_chl),
                    block.timestamp,
                    Status({
                        path: 2,
                        goodOracleCtr: 2,
                        badOracleCtr: 0,
                        tieBreakerUsed: false
                    })
                );
            }

            // If both oracles ok but not in agreement distance, try to derive
            // value via tie breaker.
            (bool ok, uint128 val) = _tryTieBreaker(val_chr, val_chl);
            if (ok) {
                return (
                    val,
                    block.timestamp,
                    Status({
                        path: 3,
                        goodOracleCtr: 2,
                        badOracleCtr: 0,
                        tieBreakerUsed: true
                    })
                );
            }

            // Otherwise not possible to decide which oracle is ok.
        } else if (ok_chr) {
            // If only chronicle ok, use chronicle's value.
            return (
                val_chr,
                block.timestamp,
                Status({
                    path: 4,
                    goodOracleCtr: 1,
                    badOracleCtr: 1,
                    tieBreakerUsed: false
                })
            );
        } else if (ok_chl) {
            // If only chainlink ok, use chainlink's value.
            return (
                val_chl,
                block.timestamp,
                Status({
                    path: 4,
                    goodOracleCtr: 1,
                    badOracleCtr: 1,
                    tieBreakerUsed: false
                })
            );
        }

        // If no oracle ok try to use twap.
        if (uniswapPool != address(0)) {
            (bool ok, uint128 twap) = _readTwap();
            if (ok) {
                return (
                    twap,
                    block.timestamp,
                    Status({
                        path: 5,
                        goodOracleCtr: 0,
                        badOracleCtr: 2,
                        tieBreakerUsed: true
                    })
                );
            }
        }

        // Otherwise no value possible.
        return (
            0,
            0,
            Status({
                path: 6,
                goodOracleCtr: 0,
                badOracleCtr: 2,
                tieBreakerUsed: false
            })
        );
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
        // assert(_DECIMALS_CHRONICLES <= decimals).
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
            uint80 roundId,
            int answer,
            /*uint startedAt*/,
            uint updatedAt,
            uint80 answeredInRound
        ) = IChainlinkAggregatorV3(chainlink).latestRoundData();
        // assert(updatedAt <= block.timestamp);

        // Fail if any of
        // - not updated in current round
        // - answer not in [1, type(uint128).max)
        // - answer stale
        if (
            answeredInRound < roundId
                || (answer <= 0 || answer >= int(uint(type(uint128).max)))
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
        answeredInRound = roundId;
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
    function setAgreementDistance(uint16 agreementDistance_) external auth {
        _setAgreementDistance(agreementDistance_);
    }

    function _setAgreementDistance(uint16 agreementDistance_) internal {
        require(agreementDistance_ != 0);
        require(agreementDistance <= _BPS);

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

    /// @dev Tries to return a value based on `a`, `b` and a tie breaker.
    ///
    /// @return bool Whether value is ok.
    /// @return uint128 Value dervied via tie breaker.
    function _tryTieBreaker(uint128 a, uint128 b)
        internal
        view
        returns (bool, uint128)
    {
        // Use pegged price heuristic if in pegged asset mode.
        if (isPeggedAsset) {
            if (a < peggedPrice) {
                if (b < peggedPrice) {
                    // [_, _, p] => val = max(a, b)
                    return (true, max(a, b));
                } else {
                    // [_, p, _] => val = p
                    return (true, peggedPrice);
                }
            } else {
                if (b < peggedPrice) {
                    // [_, p, _] => val = p
                    return (true, peggedPrice);
                } else {
                    // [p, _, _] => val = min(a, b)
                    return (true, min(a, b));
                }
            }
        }

        // Otherwise try to use twap.
        if (uniswapPool != address(0)) {
            (bool ok, uint128 twap) = _readTwap();
            if (ok) {
                if (a < twap) {
                    if (b < twap) {
                        // [_, _, twap] => val = max(a, b)
                        return (true, max(a, b));
                    } else {
                        // [_, twap, _] => val = twap
                        return (true, twap);
                    }
                } else {
                    if (b < twap) {
                        // [_, twap, _] => val = twap
                        return (true, twap);
                    } else {
                        // [twap, _, _] => val = min(a, b)
                        return (true, min(a, b));
                    }
                }
            }
        }

        // Otherwise no tie breaker possible.
        return (false, 0);
    }

    function inAgreementDistance(uint128 a, uint128 b)
        internal
        view
        returns (bool)
    {
        // Difference is 0% if both values are equal.
        if (a == b) return true;

        // Otherwise compute %-difference in basis points.
        uint diff = a > b
            ? _BPS - (((uint(b) * 1e18) / uint(a)) * _BPS / 1e18)
            : _BPS - (((uint(a) * 1e18) / uint(b)) * _BPS / 1e18);

        // And return whether %-difference inside acceptable agreement distance.
        return diff <= agreementDistance;
    }

    function median(uint128 a, uint128 b) internal pure returns (uint128) {
        // Note to cast arguments to uint to avoid overflow possibilites.
        uint sum;
        unchecked {
            sum = uint(a) + uint(b);
        }
        // assert(sum <= 2 * type(uint128).max);

        // Note that >> 1 equals a divison by 2.
        return uint128(sum >> 1);
    }

    function max(uint128 a, uint128 b) internal pure returns (uint128) {
        return a > b ? a : b;
    }

    function min(uint128 a, uint128 b) internal pure returns (uint128) {
        return a < b ? a : b;
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
        bool isPeggedAsset_,
        uint128 peggedPrice_,
        address chronicle_,
        address chainlink_,
        address uniswapPool_,
        address uniswapBaseToken_,
        address uniswapQuoteToken_,
        uint8 uniswapBaseDec_,
        uint32 uniswapLookback_,
        uint16 agreementDistance_,
        uint32 ageThreshold_
    )
        Aggor(
            initialAuthed,
            isPeggedAsset_,
            peggedPrice_,
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
