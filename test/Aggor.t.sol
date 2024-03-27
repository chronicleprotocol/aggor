// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";
import {IChronicle} from "chronicle-std/IChronicle.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {Aggor} from "src/Aggor.sol";
import {IAggor} from "src/IAggor.sol";

import {LibMedian} from "src/libs/LibMedian.sol";

import {ChronicleMock} from "./mocks/ChronicleMock.sol";
import {ChainlinkMock} from "./mocks/ChainlinkMock.sol";
import {UniswapPoolMock} from "./mocks/UniswapPoolMock.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

contract AggorTest is Test {
    Aggor aggor;

    // Contract inheriting from Aggor exposing the constructor helper function.
    // This lets forge coverage reports include the function's execution.
    Aggor_VerifyTwapConfig aggor_VerifyTwapConfig;

    // Oracle Providers:
    address chronicle = address(new ChronicleMock());
    address chainlink = address(new ChainlinkMock());

    // Twap Provider:
    address uniswapPool = address(new UniswapPoolMock());
    address uniswapBaseToken = address(new ERC20Mock("base", "base", 18));
    address uniswapQuoteToken = address(new ERC20Mock("quote", "quote", 18));
    uint32 uniswapLookback = 1 days;

    // For more info, see mocks/UniswapPoolMock::observe().
    uint valTwap = 999_902;

    // Configurations:
    uint128 agreementDistance = 9e17; // = 0.9e18 = 10%
    uint32 ageThreshold = 1 days; // 1 day

    function setUp() public {
        UniswapPoolMock(uniswapPool).setToken0(uniswapBaseToken);
        UniswapPoolMock(uniswapPool).setToken1(uniswapQuoteToken);

        // Deploy aggor.
        aggor = new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            IERC20(uniswapBaseToken).decimals(),
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        // Note to also deploy an Aggor with the constructor's
        // `_verifyTwapConfig()` function exposed.
        aggor_VerifyTwapConfig = new Aggor_VerifyTwapConfig(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            IERC20(uniswapBaseToken).decimals(),
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        // Execute Aggor's _verifyTwapConfig function for coverage reporting.
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            IERC20(uniswapBaseToken).decimals(),
            uniswapLookback
        );
    }

    // -- Test: Deployment --

    function test_Deployment_FailsIf_UniswapPoolZeroAddress() public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert("Uniswap pool must not be zero");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            address(0), // <- !
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals,
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap pool must not be zero");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            address(0), // <- !
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals,
            uniswapLookback
        );
    }

    function test_Deployment_FailsIf_BaseTokenEqualsQuoteToken() public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert("Uniswap tokens must not be equal");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapBaseToken, // <- !
            decimals,
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap tokens must not be equal");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            uniswapBaseToken,
            uniswapBaseToken, // <- !
            decimals,
            uniswapLookback
        );
    }

    function test_Deployment_FailsIf_BaseTokenNotPoolToken() public {
        address notPoolToken = address(new ERC20Mock("", "", 18));
        uint8 decimals = IERC20(notPoolToken).decimals();

        vm.expectRevert("Uniswap base token mismatch");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            notPoolToken, // <- !
            uniswapQuoteToken,
            decimals,
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap base token mismatch");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            notPoolToken, // <- !
            uniswapQuoteToken,
            decimals,
            uniswapLookback
        );
    }

    function test_Deployment_FailsIf_QuoteTokenNotPoolToken() public {
        address notPoolToken = address(new ERC20Mock("", "", 18));
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert("Uniswap quote token mismatch");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            notPoolToken, // <- !
            decimals,
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap quote token mismatch");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            uniswapBaseToken,
            notPoolToken, // <- !
            decimals,
            uniswapLookback
        );
    }

    function test_Deployment_FailsIf_BaseTokenDecimalsWrong() public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert("Uniswap base token decimals mismatch");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals + 1, // <- !
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap base token decimals mismatch");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals + 1, // <- !
            uniswapLookback
        );
    }

    function test_Deployment_FailsIf_BaseTokenDecimalsBiggerThanMaxSupportedDecimals(
    ) public {
        uniswapBaseToken = address(new ERC20Mock("base", "base", 100)); // <- !
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        UniswapPoolMock(uniswapPool).setToken0(uniswapBaseToken);

        vm.expectRevert("Uniswap base token decimals too high");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals,
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap base token decimals too high");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals,
            uniswapLookback
        );
    }

    function test_Deployment_FailsIf_UniswapLookbackBiggerThanOldestObservation(
    ) public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert("Uniswap lookback too high");
        new Aggor(
            address(this),
            address(this),
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals,
            type(uint32).max, // <- !
            agreementDistance,
            ageThreshold
        );

        vm.expectRevert("Uniswap lookback too high");
        aggor_VerifyTwapConfig.verifyTwapConfig(
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            decimals,
            type(uint32).max
        );
    }

    // -- Test: read --

    function _checkReadFunctions(
        uint wantVal,
        uint wantAge,
        IAggor.Status memory wantStatus
    ) internal {
        // latestAnswer:
        int answer = aggor.latestAnswer();
        assertEq(uint(answer), wantVal);

        // latestRoundData:
        uint80 roundId;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            aggor.latestRoundData();
        assertEq(roundId, 1);
        assertEq(uint(answer), wantVal);
        assertEq(startedAt, 0);
        assertEq(updatedAt, wantAge);
        assertEq(answeredInRound, 1);

        // readWithStatus:
        uint val;
        uint age;
        IAggor.Status memory status;
        (val, age, status) = aggor.readWithStatus();
        assertEq(val, wantVal);
        assertEq(age, wantAge);
        assertEq(status.path, wantStatus.path);
        assertEq(status.goodOracleCtr, wantStatus.goodOracleCtr);
    }

    function testFuzz_read_ChronicleOk_ChainlinkOk_InAgreementDistance(
        uint128 val,
        uint diff,
        bool diffDirection
    ) public {
        vm.assume(val != 0);
        vm.assume(val < type(uint128).max / 10 ** 18);

        // Scale val to oracles' decimals.
        uint valChr = val * 1e18;
        uint valChl = val * 1e8;

        // Let Chainlink's val have some % difference to Chronicles.
        // Note to keep vals in agreement distance.
        diff = _bound(diff, 0, 1e18 - agreementDistance);
        valChl = diffDirection
            ? valChl + (valChl * diff) / 1e18
            : valChl - (valChl * diff) / 1e18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );

        // Compute expected value.
        // Note to scale Chronicle's val down to Chainlik's decimals.
        uint wantVal = ((valChr / 1e10) + valChl) / 2;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 2, goodOracleCtr: 2});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function test_read_ChronicleOk_ChainlinkOk_InAgreementDistance_ExcplicitBoundaryChecks(
    ) public {
        // Note that the %-difference is defined from the bigger value.
        IAggor.Status memory wantStatus;
        IAggor.Status memory gotStatus;

        uint128 valChr;
        uint128 valChl;

        // -- Test: Chronicle upper boundary
        valChr = 100 * 1e18;
        valChl = 100 * 1e8;

        // 111 - 10% < 100 -> (111, 100) in agreement distance
        valChr += 11 * 1e18;
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );
        wantStatus = IAggor.Status({path: 2, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // 112 - 10% > 100 -> (112, 100) not in agreement distance
        valChr += 1 * 1e18;
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        wantStatus = IAggor.Status({path: 3, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // -- Test: Chronicle lower boundary
        valChr = 100 * 1e18;
        valChl = 100 * 1e8;

        // 100 - 10% = 90 -> (90, 100) in agreement distance
        valChr -= 10 * 1e18;
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );
        wantStatus = IAggor.Status({path: 2, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // 100 - 10% = 90 -> (89, 100) not in agreement distance
        valChr -= 1 * 1e18;
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        wantStatus = IAggor.Status({path: 3, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // -- Test: Chainlink upper boundary
        valChr = 100 * 1e18;
        valChl = 100 * 1e8;

        // 111 - 10% < 100 -> (100, 111) in agreement distance
        valChl += 11 * 1e8;
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );
        wantStatus = IAggor.Status({path: 2, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // 112 - 10% > 100 -> (100, 112) not in agreement distance
        valChl += 1 * 1e8;
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );
        wantStatus = IAggor.Status({path: 3, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // -- Test: Chainlink lower boundary
        valChr = 100 * 1e18;
        valChl = 100 * 1e8;

        // 100 - 10% = 90 -> (100, 90) in agreement distance
        valChl -= 10 * 1e8;
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );
        wantStatus = IAggor.Status({path: 2, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // 100 - 10% = 90 -> (100, 89) not in agreement distance
        valChl -= 1 * 1e8;
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );
        wantStatus = IAggor.Status({path: 3, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);
    }

    function testFuzz_read_ChronicleOk_ChainlinkOk_NotInAgreementDistance_TwapOk(
        uint128 val,
        bool diffDirection
    ) public {
        val = uint128(_bound(val, 1, type(uint128).max / 1e18));

        // Scale val to oracles' decimals.
        uint valChr = val * 1e18;
        uint valChl = val * 1e8;

        // Let values be outside of agreement distance.
        valChl = diffDirection ? 2 * valChl : valChl / 2;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );

        // Expect val is median(valChr, valChl, valTwap)
        // Note to scale Chronicle's val down to Chainlik's decimals.
        uint wantVal = LibMedian.median(
            uint128(valChr / 1e10), uint128(valChl), uint128(valTwap)
        );

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 3, goodOracleCtr: 2});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function testFuzz_read_ChronicleOk_ChainlinkOk_NotInAgreementDistance_TwapNotOk(
        uint128 val,
        bool diffDirection
    ) public {
        val = uint128(_bound(val, 1, type(uint128).max / 1e18));

        // Scale val to oracles' decimals.
        uint valChr = val * 1e18;
        uint valChl = val * 1e8;

        // Let values be outside of agreement distance.
        valChl = diffDirection ? 2 * valChl : valChl / 2;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );

        // Let twap be not ok.
        _setTwapNotOk();

        // Expect aggor to not be able to derive a value.
        uint wantVal = 0;
        uint wantAge = 0;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 6, goodOracleCtr: 0});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function testFuzz_read_ChronicleOk_ChainlinkNotOk_ValNegative(
        uint128 valChr,
        int valChl
    ) public {
        vm.assume(valChr != 0);
        vm.assume(valChr < type(uint128).max / 1e18);
        vm.assume(valChl < 0);

        // Scale Chronicle's val to 18 decimals.
        valChr *= 1e18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(int(valChl), block.timestamp);

        // Expect only Chronicle's val, scaled down to 8 decimals.
        uint wantVal = uint(valChr) / 1e10;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function testFuzz_read_ChronicleOk_ChainlinkNotOk_ValOverflow(
        uint128 valChr,
        int valChl
    ) public {
        vm.assume(valChr != 0);
        vm.assume(valChr < type(uint128).max / 1e18);
        vm.assume(uint(valChl) > type(uint128).max);

        // Scale Chronicle's val to 18 decimals.
        valChr *= 1e18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(int(valChl), block.timestamp);

        // Expect only Chronicle's val, scaled down to 8 decimals.
        uint wantVal = uint(valChr) / 1e10;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function test_read_ChronicleOk_ChainlinkNotOk_ValOverflow_ExplicitBoundaryCheck(
    ) public {
        IAggor.Status memory wantStatus;
        IAggor.Status memory gotStatus;

        // Let both oracle have some valid value.
        // However, let chainlink's val be the max valid val.
        uint128 valChr = 1e18;
        uint valChl = type(uint128).max;

        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(int(valChl), block.timestamp);

        // Expect both oracles to be valid (but not in agreement distance).
        wantStatus = IAggor.Status({path: 3, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // Let chainlink's val be invalid due to overflow.
        valChl += 1;
        ChainlinkMock(chainlink).setValAndAge(int(valChl), block.timestamp);

        // Expect only chronicle oracle to be valid.
        wantStatus = IAggor.Status({path: 4, goodOracleCtr: 1});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);
    }

    function testFuzz_read_ChronicleOk_ChainlinkNotOk_ValStale(
        uint128 valChr,
        uint128 valChl
    ) public {
        vm.assume(valChr != 0);
        vm.assume(valChr < type(uint128).max / 1e18);

        // Scale Chronicle's val to 18 decimals.
        valChr *= 1e18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        // Note to use stale timestamp.
        ChainlinkMock(chainlink).setValAndAge(int(uint(valChl)), 0);

        // Expect only Chronicle's val, scaled down to 8 decimals.
        uint wantVal = uint(valChr) / 1e10;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function test_read_ChronicleOk_ChainlinkNotOk_ValStale_ExplicitBoundaryCheck(
    ) public {
        IAggor.Status memory wantStatus;
        IAggor.Status memory gotStatus;

        // Let both oracles have some valid value.
        uint128 valChr = 100 * 1e18;
        uint128 valChl = 100 * 1e8;

        // Let both oracle be non-stale.
        // However, let chainlink's age be the oldest still valid age.
        uint ageChr = block.timestamp;
        uint ageChl = block.timestamp - ageThreshold;

        ChronicleMock(chronicle).setValAndAge(valChr, ageChr);
        ChainlinkMock(chainlink).setValAndAge(int(uint(valChl)), ageChl);

        // Expect both oracles to be valid (and in agreement distance).
        wantStatus = IAggor.Status({path: 2, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // Let chainlink's value be stale.
        ageChl -= 1;
        ChainlinkMock(chainlink).setValAndAge(int(uint(valChl)), ageChl);

        // Expect only chronicle oracle to be valid.
        wantStatus = IAggor.Status({path: 4, goodOracleCtr: 1});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);
    }

    function testFuzz_read_ChronicleNotOk_ChainlinkOk(
        uint128 valChr,
        uint128 valChl
    ) public {
        vm.assume(valChl != 0);

        // Set vals.
        // Note to set Chronicle's ok to false.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChronicleMock(chronicle).setOk(false);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );

        // Expect only Chainlink's val.
        uint wantVal = uint(valChl);

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function testFuzz_read_ChronicleNotOk_ChainlinkOk_ValStale(
        uint128 valChr,
        uint128 valChl
    ) public {
        vm.assume(valChl != 0);

        // Set vals.
        // Note to let Chronicle's val be stale.
        ChronicleMock(chronicle).setValAndAge(valChr, 0);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );

        // Expect only Chainlink's val.
        uint wantVal = uint(valChl);

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function test_read_ChronicleNotOk_ChainlinkOk_ValStale_ExplicitBoundaryCheck(
    ) public {
        IAggor.Status memory wantStatus;
        IAggor.Status memory gotStatus;

        // Let both oracles have some valid value.
        uint128 valChr = 100 * 1e18;
        uint128 valChl = 100 * 1e8;

        // Let both oracle be non-stale.
        // However, let chronicles's age be the oldest still valid age.
        uint ageChr = block.timestamp - ageThreshold;
        uint ageChl = block.timestamp;

        ChronicleMock(chronicle).setValAndAge(valChr, ageChr);
        ChainlinkMock(chainlink).setValAndAge(int(uint(valChl)), ageChl);

        // Expect both oracles to be valid (and in agreement distance).
        wantStatus = IAggor.Status({path: 2, goodOracleCtr: 2});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);

        // Let chronicle's value be stale.
        ageChr -= 1;
        ChronicleMock(chronicle).setValAndAge(valChr, ageChr);

        // Expect only chainlink oracle to be valid.
        wantStatus = IAggor.Status({path: 4, goodOracleCtr: 1});
        (,, gotStatus) = aggor.readWithStatus();
        assertEq(wantStatus.path, gotStatus.path);
        assertEq(wantStatus.goodOracleCtr, gotStatus.goodOracleCtr);
    }

    function test_read_ChronicleNotOk_ChainlinkOk_NotTolled() public {
        // Let aggor not be toll'ed on Chronicle.
        ChronicleMock(chronicle).setTolled(false);

        // Set Chainlink's val.
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(type(uint128).max)), block.timestamp
        );

        // Expect only Chainlink's val.
        uint wantVal = uint(type(uint128).max);

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function test_read_ChronicleNotOk_ChainlinkNotOk_TwapOk() public {
        // Let Chronicle's and Chainlink's val be not ok.
        // Use timestamp of zero to make vals stale.
        ChronicleMock(chronicle).setValAndAge(1, 0);
        ChainlinkMock(chainlink).setValAndAge(1, 0);

        uint wantVal = valTwap;
        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 5, goodOracleCtr: 0});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function test_read_ChronicleNotOk_ChainlinkNotOk_TwapNotOk() public {
        // Let Chronicle's and Chainlink's val be not ok.
        // Use timestamp of zero to make vals stale.
        ChronicleMock(chronicle).setValAndAge(1, 0);
        ChainlinkMock(chainlink).setValAndAge(1, 0);

        // Let TWAP val be not ok.
        _setTwapNotOk();

        uint wantVal = 0;
        uint wantAge = 0;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 6, goodOracleCtr: 0});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    // -- Auth'ed Functionality --

    function testFuzz_setAgreementDistance(uint128 agreementDistance_) public {
        vm.assume(agreementDistance_ != 0);
        vm.assume(agreementDistance_ <= 1e18);

        aggor.setAgreementDistance(agreementDistance_);
        assertEq(aggor.agreementDistance(), agreementDistance_);
    }

    function test_setAgreementDistance_RevertsIf_AgreementDistanceZero()
        public
    {
        vm.expectRevert();
        aggor.setAgreementDistance(0);
    }

    function testFuzz_setAgreementDistance_RevertsIf_AgreementDistanceMoreThan1WAD(
        uint128 agreementDistance_
    ) public {
        vm.assume(agreementDistance_ > 1e18);

        vm.expectRevert();
        aggor.setAgreementDistance(agreementDistance_);
    }

    function test_setAgreementDistance_RevertsIf_AgreementDistanceMoreThan1Wad_ExplicitBoundaryCheck(
    ) public {
        vm.expectRevert();
        aggor.setAgreementDistance(1e18 + 1);

        aggor.setAgreementDistance(1e18);
    }

    function test_setAgreementDistance_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.setAgreementDistance(1);
    }

    function testFuzz_setAgeThreshold(uint32 ageThreshold_) public {
        vm.assume(ageThreshold_ != 0);

        aggor.setAgeThreshold(ageThreshold_);
        assertEq(aggor.ageThreshold(), ageThreshold_);
    }

    function test_setAgeThreshold_RevertsIf_AgeThresholdZero() public {
        vm.expectRevert();
        aggor.setAgeThreshold(0);
    }

    function test_setAgeThreshold_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.setAgeThreshold(1);
    }

    // -- Toll'ed Functionality --

    function test_latestRoundData_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.latestRoundData();
    }

    function test_latestAnswer_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.latestAnswer();
    }

    function test_readWithStatus_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.readWithStatus();
    }

    // -- IToll Functionality --

    function test_kiss_IsDisabled() public {
        vm.expectRevert();
        aggor.kiss(address(0xbeef));
    }

    function test_diss_IsDisabled() public {
        vm.expectRevert();
        aggor.diss(address(0xbeef));
    }

    function test_tolled_OnlyBudAndZeroAddress() public {
        // Check via tolled(address)(bool).
        assertTrue(aggor.tolled(address(0)));
        assertTrue(aggor.tolled(address(this)));

        // Check via tolled()(address[]).
        address[] memory tolled = aggor.tolled();
        assertEq(tolled.length, 2);
        assertEq(tolled[0], address(0));
        assertEq(tolled[1], address(this));

        // Check via bud(address)(uint).
        assertEq(aggor.bud(address(0)), 1);
        assertEq(aggor.bud(address(this)), 1);
    }

    // -- Internal Helpers --

    function _setTwapNotOk() public {
        // See mocks/UniswapPoolMock::oberseve().
        UniswapPoolMock(uniswapPool).setShouldOverflowUint128(true);
    }
}

contract Aggor_VerifyTwapConfig is Aggor {
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
    )
        Aggor(
            initialAuthed,
            bud_,
            chronicle_,
            chainlink_,
            uniswapPool_,
            uniswapBaseToken_,
            uniswapQuoteToken_,
            uniswapBaseTokenDecimals_,
            uniswapLookback_,
            agreementDistance_,
            ageThreshold_
        )
    {}

    function verifyTwapConfig(
        address uniswapPool_,
        address uniswapBaseToken_,
        address uniswapQuoteToken_,
        uint8 uniswapBaseTokenDecimals_,
        uint32 uniswapLookback_
    ) public view {
        _verifyTwapConfig(
            uniswapPool_,
            uniswapBaseToken_,
            uniswapQuoteToken_,
            uniswapBaseTokenDecimals_,
            uniswapLookback_
        );
    }
}
