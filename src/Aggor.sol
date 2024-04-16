// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Auth} from "chronicle-std/auth/Auth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

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
 * @notice Oracle aggregator distributing trust among different oracle providers
 *
 * @dev While Chronicle oracles normally use the chronicle-std/Toll module for
 *      access controlling read functions, this implementation adopts a
 *      non-configurable, inlined approach. Two addresses are granted read access:
 *      the zero address and `_bud`, which are immutably set during deployment.
 *
 *      Nevertheless, the full IToll interface is implemented to ensure compatibility.
 *
 * @author Chronicle Labs, Inc
 * @custom:security-contact security@chroniclelabs.org
 */
contract Aggor is IAggor, IToll, Auth {
    using LibUniswapOracles for address;

    // -- Internal Constants --

    /// @dev The maximum number of decimals for Uniswap's base asset supported.
    uint internal constant _MAX_UNISWAP_BASE_DECIMALS = 38;

    /// @dev The decimals value used by Chronicle Protocol oracles.
    uint8 internal constant _DECIMALS_CHRONICLE = 18;

    // -- Immutable Configurations --

    // -- Chainlink Compatibility

    /// @inheritdoc IAggor
    uint8 public constant decimals = 8;

    // -- Toll

    /// @dev Bud is the only non-zero address being toll'ed.
    address internal immutable _bud;

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
    uint128 public agreementDistance;
    /// @inheritdoc IAggor
    uint32 public ageThreshold;

    // -- Modifier --

    modifier toll() {
        if (msg.sender != _bud && msg.sender != address(0)) {
            revert NotTolled(msg.sender);
        }
        _;
    }

    // -- Constructor --

    constructor(
        address initialAuthed,
        address bud_,
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
        _bud = bud_;
        chronicle = chronicle_;
        chainlink = chainlink_;
        uniswapPool = uniswapPool_;
        uniswapBaseToken = uniswapBaseToken_;
        uniswapQuoteToken = uniswapQuoteToken_;
        uniswapBaseTokenDecimals = uniswapBaseTokenDecimals_;
        uniswapLookback = uniswapLookback_;

        // Emit events indicating address(0) and _bud are tolled.
        // Note to use address(0) as caller to indicate address was toll'ed
        // during deployment.
        emit TollGranted(address(0), address(0));
        emit TollGranted(address(0), _bud);

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
        require(uniswapPool_ != address(0), "Uniswap pool must not be zero");

        address token0 = IUniswapV3Pool(uniswapPool_).token0();
        address token1 = IUniswapV3Pool(uniswapPool_).token1();

        // Verify base and quote tokens.
        require(
            uniswapBaseToken_ != uniswapQuoteToken_,
            "Uniswap tokens must not be equal"
        );
        require(
            uniswapBaseToken_ == token0 || uniswapBaseToken_ == token1,
            "Uniswap base token mismatch"
        );
        require(
            uniswapQuoteToken_ == token0 || uniswapQuoteToken_ == token1,
            "Uniswap quote token mismatch"
        );

        // Verify base token's decimals.
        require(
            uniswapBaseTokenDecimals_ == IERC20(uniswapBaseToken_).decimals(),
            "Uniswap base token decimals mismatch"
        );
        require(
            uniswapBaseTokenDecimals_ <= _MAX_UNISWAP_BASE_DECIMALS,
            "Uniswap base token decimals too high"
        );

        // Verify TWAP is initialized.
        // Specifically, verify that the TWAP's oldest observation is older
        // then the uniswapLookback argument.
        uint32 oldestObservation = uniswapPool_.getOldestObservationSecondsAgo();
        require(
            oldestObservation > uniswapLookback_, "Uniswap lookback too high"
        );
    }

    // -- Read Functionality --

    /// @dev Returns Aggor's derived value, timestamp and status information.
    ///
    /// @dev Note that the value's age is always block.timestamp except if the
    ///      value itself is invalid.
    ///
    /// @return uint128 Aggor's current value.
    /// @return uint The value's age.
    /// @return Status The status information.
    function _read() internal view returns (uint128, uint, Status memory) {
        // Read Chronicle and Chainlink oracles.
        (bool okChr, uint128 valChr) = _readChronicle();
        (bool okChl, uint128 valChl) = _readChainlink();

        uint age = block.timestamp;

        if (okChr && okChl) {
            // If both oracles ok and in agreement distance, return their median.
            if (_inAgreementDistance(valChr, valChl)) {
                return (
                    LibMedian.median(valChr, valChl),
                    age,
                    Status({path: 2, goodOracleCtr: 2})
                );
            }

            // If both oracles ok but not in agreement distance, derive value
            // using TWAP as tie breaker.
            (bool okTwap, uint128 valTwap) = _readTwap();
            if (okTwap) {
                return (
                    LibMedian.median(valChr, valChl, valTwap),
                    age,
                    Status({path: 3, goodOracleCtr: 2})
                );
            }

            // Otherwise not possible to decide which oracle is ok.
        } else if (okChr) {
            // If only Chronicle ok, use Chronicle's value.
            return (valChr, age, Status({path: 4, goodOracleCtr: 1}));
        } else if (okChl) {
            // If only Chainlink ok, use Chainlink's value.
            return (valChl, age, Status({path: 4, goodOracleCtr: 1}));
        }

        // If no oracle ok use TWAP.
        (bool ok, uint128 twap) = _readTwap();
        if (ok) {
            return (twap, age, Status({path: 5, goodOracleCtr: 0}));
        }

        // Otherwise no value derivation possible.
        return (0, 0, Status({path: 6, goodOracleCtr: 0}));
    }

    /// @dev Reads the Chronicle oracle.
    ///
    /// @dev Note that while chronicle uses 18 decimals, the returned value is
    ///      already scaled to `decimals`.
    ///
    /// @return bool Whether oracle is ok.
    /// @return uint128 The oracle's val.
    function _readChronicle() internal view returns (bool, uint128) {
        // Note that Chronicle's `try...` functions revert iff the caller is not
        // toll'ed.
        try IChronicle(chronicle).tryReadWithAge() returns (
            bool ok, uint val, uint age
        ) {
            // assert(val <= type(uint128).max);
            // assert(!ok || val != 0); // ok -> val != 0
            // assert(age <= block.timestamp);

            // Fail if not ok or value stale.
            if (!ok || age + ageThreshold < block.timestamp) {
                return (false, 0);
            }

            // Scale value down from Chronicle decimals to Aggor decimals.
            // assert(_DECIMALS_CHRONICLES >= decimals).
            val /= 10 ** (_DECIMALS_CHRONICLE - decimals);

            return (true, uint128(val));
        } catch {
            // assert(!IToll(chronicle).tolled(address(this)));
            return (false, 0);
        }
    }

    /// @dev Reads the Chainlink oracle.
    ///
    /// @return bool Whether oracle is ok.
    /// @return uint128 The oracle's val.
    function _readChainlink() internal view returns (bool, uint128) {
        // !!! IMPORTANT WARNING !!!
        //
        // This function implementation MUST NOT be used when the Chainlink
        // oracle's implementation is behind a proxy!
        //
        // Otherwise a malicious contract update is possible via which every
        // read will fail. Note that this vulnerability _cannot_ be fixed via
        // using try-catch as of version 0.8.24. This is because the abi.decoding
        // of the return data is "outside" the try-block.
        //
        // The only way to fully protect against malicious contract updates is
        // via using a low-level staticcall with _manual_ returndata decoding!
        //
        // Note that the trust towards Chainlink not performing a malicious
        // contract update is different from the trust to not maliciously update
        // the oracle's configuration. While the latter can lead to invalid and
        // malicious price updates, the first may lead to a total
        // denial-of-service for protocols reading the proxy.

        try IChainlinkAggregatorV3(chainlink).latestRoundData() returns (
            uint80, /*roundId*/
            int answer,
            uint, /*startedAt*/
            uint updatedAt,
            uint80 /*answeredInRound*/
        ) {
            // Decide whether value is stale.
            // Unchecked to circumvent revert due to overflow. Overflow otherwise
            // no issue as updatedAt is solely controlled by Chainlink anyway.
            bool isStale;
            unchecked {
                isStale = updatedAt + ageThreshold < block.timestamp;
            }

            // Fail if answer stale or not in [1, type(uint128).max].
            if (
                isStale || answer <= 0 || uint(answer) > uint(type(uint128).max)
            ) {
                return (false, 0);
            }

            // Otherwise ok.
            return (true, uint128(uint(answer)));
        } catch {
            return (false, 0);
        }
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

    // -- IToll Functionality --

    /// @inheritdoc IToll
    /// @dev Function is disabled!
    function kiss(address /*who*/ ) external view auth {
        revert();
    }

    /// @inheritdoc IToll
    /// @dev Function is disabled!
    function diss(address /*who*/ ) external view auth {
        revert();
    }

    /// @inheritdoc IToll
    function tolled(address who) public view returns (bool) {
        return who == _bud || who == address(0);
    }

    /// @inheritdoc IToll
    function tolled() external view returns (address[] memory) {
        address[] memory result = new address[](2);
        result[0] = address(0);
        result[1] = _bud;

        return result;
    }

    /// @inheritdoc IToll
    function bud(address who) external view returns (uint) {
        return tolled(who) ? 1 : 0;
    }

    // -- Internal Helpers --

    function _inAgreementDistance(uint128 a, uint128 b)
        internal
        view
        returns (bool)
    {
        if (a > b) {
            return uint(b) * 1e18 >= agreementDistance * uint(a);
        } else {
            return uint(a) * 1e18 >= agreementDistance * uint(b);
        }
    }
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
        address bud_,
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
            bud_,
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
