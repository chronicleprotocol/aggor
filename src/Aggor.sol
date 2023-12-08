// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "chronicle-std/IChronicle.sol";
import {Auth} from "chronicle-std/auth/Auth.sol";
import {Toll} from "chronicle-std/toll/Toll.sol";

import {LibCalc} from "./libs/LibCalc.sol";

import {IAggor} from "./IAggor.sol";

/**
 * @title Aggor
 *
 * @notice Aggor combines oracle values from multiple providers into a single
 *         value
 */
contract Aggor is IAggor, Auth, Toll {
    // -- Internal Types --

    /// @dev PriceData encapsulated an oracle's val and age.
    struct PriceData {
        uint val;
        uint age;
    }

    // -- Constants & Immutables --

    /// @dev Decimals used in Chainlink compatibility functions.
    uint internal constant _DECIMALS_CHAINLINK = 8;

    /// @dev Percentage scale is in basis points (BPS).
    uint16 internal constant _BPS = 10_000;

    /// @inheritdoc IAggor
    uint8 public constant decimals = 18;

    /// @inheritdoc IChronicle
    bytes32 public immutable wat;

    /// @inheritdoc IAggor
    bool public immutable isPeggedAsset;

    // -- Storage --

    // TODO: Why agreement distance not set in constructor?
    // TODO: Rename to threshold?
    /// @inheritdoc IAggor
    uint public agreementDistance;

    /// @inheritdoc IAggor
    address public twap;

    /// @inheritdoc IAggor
    uint public acceptableAgeThreshold;

    /// @dev The set of Oracles from which prices are queried.
    address[] internal _oracles;

    // -- Constructor --

    constructor(
        address initialAuthed,
        bytes32 wat_,
        address[] memory oracles_,
        address twap_,
        uint acceptableAgeThreshold_,
        bool isPeggedAsset_
    ) Auth(initialAuthed) {
        // Set immutables.
        wat = wat_;
        isPeggedAsset = isPeggedAsset_;

        // Set configurations.
        _setOracles(oracles_);
        _setTwap(twap_);
        _setAcceptableAgeThreshold(acceptableAgeThreshold_);
    }

    // -- Read Functionality --

    function _read() internal view returns (uint, uint, StatusInfo memory) {
        // Price encapsulates the val and age, and status introspect data,
        // returned by the function.
        PriceData memory price;
        StatusInfo memory status;

        // Allocate memory array for price datas with capacity for each oracle
        // plus one extra slot. The extra slot may be used by a tie-breaker, ie
        // either twap or pegged asset heuristic.
        //
        // The array will be "shortened" via updating its length to the actual
        // number of prices included.
        PriceData[] memory prices = new PriceData[](_oracles.length + 1);
        uint pricesCtr;

        // Return values of an IChronicle::tryReadWithAge() call.
        // Note that each oracle is abstracted via an IChronicle interface
        // adapter.
        bool ok;
        uint val;
        uint age;

        // Try reading each oracle.
        for (uint i; i < _oracles.length; i++) {
            (ok, val, age) = IChronicle(_oracles[i]).tryReadWithAge();

            if (ok && _ageOk(age)) {
                prices[pricesCtr++] = PriceData(val, age);
            } else {
                status.countFailedOraclePrices++;
            }
        }

        // Store number of successful oracle reads in status struct.
        status.countGoodOraclePrices = pricesCtr;

        if (pricesCtr >= 3) {
            // == Level 1 ==
            // Good prices : >= 3
            // Result      : median(prices)
            status.returnLevel = 1;

            price = _median(_shorten(prices, pricesCtr));
            return (price.val, price.age, status);
        }

        if (pricesCtr == 2) {
            if (
                LibCalc.pctDiff(
                    uint128(prices[0].val), uint128(prices[1].val), _BPS
                ) <= agreementDistance
            ) {
                // == Level 2 ==
                // Good prices : 2 with both values in agreement distance
                // Result      : median(prices)
                status.returnLevel = 2;

                price.val = (prices[0].val + prices[1].val) / 2;
                price.age = prices[0].age > prices[1].age
                        ? prices[1].age
                        : prices[0].age;

                return (price.val, price.age, status);
            } else {
                // == Level 3 ==
                // Good prices : 2 with both values NOT in agreement distance
                // Result      : median(price ++ tiebreaker)
                //
                // Note that tie breaker may be either a pegged price heuristic
                // (if Aggor is running in pegged asset mode) or a twap (if set).
                //
                // If no tie breaker exists level 6 will be reached, ie the oracle
                // read failed and no price is returned.
                status.returnLevel = 3;

                if (isPeggedAsset) {
                    // Note that pegged asset mode assumes a price of 1:1.
                    // Pegged asset heuristic is to add a price of 1 (ie 1e18)
                    // manually into the price list and using the median of the
                    // list afterwards.
                    prices[pricesCtr++] = PriceData(1e18, block.timestamp);
                    price = _median(_shorten(prices, pricesCtr++));
                    return (price.val, price.age, status);
                }

                if (twap != address(0)) {
                    (ok, val, age) = IChronicle(twap).tryReadWithAge();

                    if (ok && _ageOk(age)) {
                        prices[pricesCtr++] = PriceData(val, age);
                        status.twapUsed = true;
                        price = _median(_shorten(prices, pricesCtr));
                        return (price.val, price.age, status);
                    }
                }
            }
        }

        if (pricesCtr == 1) {
            // == Level 4 ==
            // Good price : 1
            // Result     : prices[0]
            status.returnLevel = 4;
            return (prices[0].val, prices[0].age, status);
        }

        if (twap != address(0)) {
            // == Level 5 ==
            // Good price : 0
            // Result     : twap
            (ok, val, age) = IChronicle(twap).tryReadWithAge();

            if (ok && _ageOk(age)) {
                status.returnLevel = 5;
                status.twapUsed = true;
                return (val, age, status);
            }
        }

        // == Level 6 ==
        // Good price : 0
        // Result     : Failure
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
        return
            _toInt(uint128(LibCalc.scale(val, decimals, _DECIMALS_CHAINLINK)));
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

    /// @inheritdoc IAggor
    function setAcceptableAgeThreshold(uint acceptableAgeThreshold_)
        external
        auth
    {
        _setAcceptableAgeThreshold(acceptableAgeThreshold_);
    }

    function _setAcceptableAgeThreshold(uint acceptableAgeThreshold_)
        internal
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
        for (uint i; i < oracles_.length; i++) {
            require(oracles_[i] != address(0));
            _oracles[i] = oracles_[i];
        }
        emit OraclesUpdated(msg.sender, oldLen, oracles_.length);
    }

    /// @inheritdoc IAggor
    function setTwap(address twap_) external auth {
        _setTwap(twap_);
    }

    function _setTwap(address twap_) internal {
        if (twap != twap_) {
            emit TwapUpdated(msg.sender, twap, twap_);
            twap = twap_;
        }
    }

    // -- Public View Functions --

    /// @inheritdoc IAggor
    function oracles() external view returns (address[] memory) {
        return _oracles;
    }

    // -- Internal Helpers --

    function _toInt(uint128 val) internal pure returns (int) {
        // Note that int(type(uint128).max) == type(uint128).max.
        return int(uint(val));
    }

    function _shorten(PriceData[] memory a, uint len)
        internal
        pure
        returns (PriceData[] memory)
    {
        assert(len <= a.length);
        //if (len >= a.length) return a;
        assembly {
            mstore(a, len)
        }
        return a;
    }

    function _ageOk(uint age) internal view returns (bool) {
        // Age is ok if its not from the future and the threshold check
        // succeeds.
        return age <= block.timestamp
            ? (block.timestamp - age) <= acceptableAgeThreshold
            : false;
    }

    function _median(PriceData[] memory prices)
        internal
        view
        returns (PriceData memory)
    {
        PriceData[] memory sorted = _quickSort(prices, 0, prices.length - 1);

        uint half = sorted.length / 2;

        if (sorted.length % 2 == 0) {
            PriceData memory a = sorted[half - 1];
            PriceData memory b = sorted[half];

            // forgefmt: disable-next-item
            uint median = (a.val / 2)
                        + (b.val / 2)
                        + (((a.val % 2) + (b.val % 2)) / 2);

            // TODO: Comment about age.
            uint age = a.age > b.age ? b.age : a.age;

            return PriceData({val: median, age: age});
        } else {
            return sorted[half];
        }
    }

    function _quickSort(PriceData[] memory price, uint left, uint right)
        internal
        view
        returns (PriceData[] memory)
    {
        uint i = left;
        uint j = right;
        if (i == j) return price;
        uint pivot = price[left + (right - left) / 2].val;
        while (i <= j) {
            while (price[i].val < pivot) i++;
            while (pivot < price[j].val) j--;
            if (i <= j) {
                (price[i], price[j]) = (price[j], price[i]);
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
