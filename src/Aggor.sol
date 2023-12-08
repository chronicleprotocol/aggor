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
    uint8 public constant decimals = 18;

    /// @inheritdoc IChronicle
    bytes32 public immutable wat;

    /// @inheritdoc IAggor
    uint public agreementDistance;

    /// @inheritdoc IAggor
    bool public isPeggedAsset;

    /// @inheritdoc IAggor
    address public twap;

    /// @inheritdoc IAggor
    uint public acceptableAgeThreshold;

    /// @notice The set of Oracles from which we will query price.
    address[] internal _oracles;

    /// @dev We track both age and price together, this struct pairs them which
    //       can then be sorted, picked for median, etc.
    struct PriceData {
        uint val;
        uint age;
    }

    constructor(
        address initialAuthed,
        bytes32 wat_,
        address[] memory oracles_,
        address twap_,
        uint acceptableAgeThreshold_,
        bool isPeggedAsset_
    ) Auth(initialAuthed) {
        _setOracles(oracles_);

        wat = wat_;
        twap = twap_;
        isPeggedAsset = isPeggedAsset_;
        acceptableAgeThreshold = acceptableAgeThreshold_;
    }

    // -- Read Functionality --

    function _read() internal view returns (uint, uint, StatusInfo memory) {
        // Instrospect and track status of this workflow
        StatusInfo memory status;

        /// @dev In-memory arrays don't have push() so instantiate with enough slots
        /// for all prices. Then we will _shorten() to get "pushed" prices. You
        /// MUST increment goodPricesTotal whenever goodPrices is assigned a price.
        PriceData[] memory goodPrices = new PriceData[](_oracles.length + 1);
        uint goodPricesTotal;

        bool ok;
        uint val;
        uint age;

        for (uint i = 0; i < _oracles.length; i++) {
            (ok, val, age) = IChronicle(_oracles[i]).tryReadWithAge();
            if (
                ok && val != 0 && age <= block.timestamp
                    && (block.timestamp - age) <= acceptableAgeThreshold
            ) {
                goodPrices[goodPricesTotal++] = PriceData(val, age);
            } else {
                status.countFailedOraclePrices++;
            }
        }

        status.countGoodOraclePrices = goodPricesTotal;

        // Preferred scenario, will fall through to less desirable ones below.
        if (goodPricesTotal >= 3) {
            PriceData memory price =
                _median(_shorten(goodPrices, goodPricesTotal));
            status.returnLevel = 1;
            return (price.val, price.age, status);
        }

        if (goodPricesTotal == 2) {
            // Try to return mean of Oracles:
            // Prices from the Oracles MUST be within the agreement distance (%)
            if (
                LibCalc.pctDiff(
                    uint128(goodPrices[0].val),
                    uint128(goodPrices[1].val),
                    _pscale
                ) <= agreementDistance
            ) {
                status.returnLevel = 2;
                return (
                    (goodPrices[0].val + goodPrices[1].val) / 2,
                    goodPrices[0].age,
                    status
                );
            } else {
                // Otherwise, use alternate methods to obtain median:
                status.returnLevel = 3;
                if (isPeggedAsset) {
                    // NOTE(jamesr) Aggor treats all price values as having 18
                    // decimals, at least until necessary to scale down, e.g.
                    // the return from latestAnswer(). So the notion of
                    // "inserting 1 into the price set for median" really means
                    // inserting 1 ether.
                    goodPrices[goodPricesTotal++] =
                        PriceData(1 ether, block.timestamp);
                    PriceData memory price =
                        _median(_shorten(goodPrices, goodPricesTotal));
                    return (price.val, price.age, status);
                }
                if (twap != address(0)) {
                    (ok, val, age) = IChronicle(twap).tryReadWithAge();
                    if (ok) {
                        goodPrices[goodPricesTotal++] = PriceData(val, age);
                        status.twapUsed = true;
                        PriceData memory price =
                            _median(_shorten(goodPrices, goodPricesTotal));
                        return (price.val, price.age, status);
                    }
                }
            }
        }

        // If only one oracle with good data, return that
        if (goodPricesTotal == 1) {
            status.returnLevel = 4;
            return (goodPrices[0].val, goodPrices[0].age, status);
        }

        // Last attempt to get price, return TWAP if possible.
        if (twap != address(0)) {
            (ok, val, age) = IChronicle(twap).tryReadWithAge();
            if (
                ok && age <= block.timestamp // Can't be from the future
                    && (block.timestamp - age) <= acceptableAgeThreshold
            ) {
                status.twapUsed = true;
                status.returnLevel = 5;
                return (val, age, status);
            }
        }

        // Finally, no price could be obtained. The defi world has ended,
        // probably in fire.
        status.returnLevel = 6;
        return (0, 0, status);
    }

    // -- IChronicle

    /// @inheritdoc IChronicle
    function read() external view toll returns (uint) {
        (uint val,,) = _read();
        require(val != 0);
        return val;
    }

    /// @inheritdoc IChronicle
    function tryRead() external view toll returns (bool, uint) {
        (uint val,,) = _read();
        return (val != 0, val);
    }

    /// @inheritdoc IChronicle
    function readWithAge() external view toll returns (uint, uint) {
        (uint val, uint age,) = _read();
        require(val != 0);
        return (val, age);
    }

    /// @inheritdoc IChronicle
    function tryReadWithAge() external view toll returns (bool, uint, uint) {
        (uint val, uint age,) = _read();
        return (val != 0, val, age);
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
        (uint val, uint age,) = _read();
        answer = _toInt(uint128(val));
        startedAt = 0;
        updatedAt = age;
        answeredInRound = roundId;
    }

    /// @inheritdoc IAggor
    function latestAnswer() external view toll returns (int) {
        (uint val,,) = _read();
        return _toInt(uint128(LibCalc.scale(val, decimals, 8)));
    }

    // -- IAggor

    /// @inheritdoc IAggor
    function readWithStatus()
        external
        view
        toll
        returns (uint, uint, StatusInfo memory)
    {
        return _read();
    }

    // -- Auth'ed Functionality --

    /// @inheritdoc IAggor
    function setAgreementDistance(uint agreementDistance_) external auth {
        _setAgreementDistance(agreementDistance_);
    }

    function _setAgreementDistance(uint agreementDistance_) internal {
        require(agreementDistance_ != 0);

        if (agreementDistance != agreementDistance_) {
            emit AgreementDistanceUpdated(
                msg.sender, agreementDistance, agreementDistance_
            );
            agreementDistance = agreementDistance_;
        }
    }

    function setAcceptableAgeThreshold(uint acceptableAgeThreshold_)
        external
        auth
    {
        _setAcceptableAgeThreshold(acceptableAgeThreshold_);
    }

    function _setAcceptableAgeThreshold(uint acceptableAgeThreshold_)
        internal
        auth
    {
        require(acceptableAgeThreshold_ != 0);

        if (acceptableAgeThreshold != acceptableAgeThreshold_) {
            emit AcceptableAgeThresholdUpdated(
                msg.sender, acceptableAgeThreshold, acceptableAgeThreshold_
            );
            acceptableAgeThreshold = acceptableAgeThreshold_;
        }
    }

    /// @inheritdoc IAggor
    function setOracles(address[] memory oracles_) external auth {
        _setOracles(oracles_);
    }

    function _setOracles(address[] memory oracles_) internal {
        uint oldLen = _oracles.length;
        _oracles = new address[](oracles_.length);
        for (uint i = 0; i < oracles_.length; i++) {
            require(oracles_[i] != address(0));
            _oracles[i] = oracles_[i];
        }
        emit OraclesUpdated(msg.sender, oldLen, oracles_.length);
    }

    /// @inheritdoc IAggor
    function setTwap(address twap_) external auth {
        emit TwapUpdated(msg.sender, twap, twap_);
        twap = twap_;
    }

    /// @inheritdoc IAggor
    function oracles() external view returns (address[] memory) {
        return _oracles;
    }

    // -- Private Helpers --
    function _toInt(uint128 val) internal pure returns (int) {
        // Note that int(type(uint128).max) == type(uint128).max.
        return int(uint(val));
    }

    function _shorten(PriceData[] memory a, uint len)
        internal
        pure
        returns (PriceData[] memory)
    {
        if (len >= a.length) return a;
        assembly {
            mstore(a, len)
        }
        return a;
    }

    function _median(PriceData[] memory price)
        internal
        view
        returns (PriceData memory)
    {
        PriceData[] memory res =
            _quickSort(price, int(0), int(price.length - 1));
        if (res.length % 2 == 0) {
            uint a = res[(res.length / 2) - 1].val;
            uint b = res[(res.length / 2)].val;
            uint distMedian = (a / 2) + (b / 2) + (((a % 2) + (b % 2)) / 2);
            return
                PriceData({val: distMedian, age: res[(res.length / 2) - 1].age});
        } else {
            return res[res.length / 2];
        }
    }

    function _quickSort(PriceData[] memory price, int left, int right)
        internal
        view
        returns (PriceData[] memory)
    {
        int i = left;
        int j = right;
        if (i == j) return price;
        uint pivot = price[uint(left + (right - left) / 2)].val;
        while (i <= j) {
            while (price[uint(i)].val < pivot) i++;
            while (pivot < price[uint(j)].val) j--;
            if (i <= j) {
                (price[uint(i)], price[uint(j)]) =
                    (price[uint(j)], price[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j) _quickSort(price, left, j);
        if (i < right) _quickSort(price, i, right);
        return price;
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
contract Aggor_COUNTER is Aggor {
    // @todo   ^^^^^^^ Adjust name of Aggor instance
    constructor(
        address initialAuthed,
        bytes32 wat_,
        address[] memory oracles_,
        address twap_,
        uint acceptableAgeThreshold_,
        bool isPeggedAsset_
    )
        Aggor(
            initialAuthed,
            wat_,
            oracles_,
            twap_,
            acceptableAgeThreshold_,
            isPeggedAsset_
        )
    {}
}
