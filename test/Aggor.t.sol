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
    uint128 agreementDistance = 1e17; // 10%
    uint32 ageThreshold = 1 days; // 1 day

    function setUp() public {
        UniswapPoolMock(uniswapPool).setToken0(uniswapBaseToken);
        UniswapPoolMock(uniswapPool).setToken1(uniswapQuoteToken);

        // Deploy aggor.
        aggor = new Aggor(
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

        // Note to kiss address(this) on aggor.
        aggor.kiss(address(this));
    }

    // -- Test: Deployment --

    function test_Deployment_FailsIf_UniswapPoolZeroAddress() public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert();
        new Aggor(
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
    }

    function test_Deployment_FailsIf_BaseTokenEqualsQuoteToken() public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert();
        new Aggor(
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
    }

    function test_Deployment_FailsIf_BaseTokenNotPoolToken() public {
        address notPoolToken = address(new ERC20Mock("", "", 18));
        uint8 decimals = IERC20(notPoolToken).decimals();

        vm.expectRevert();
        new Aggor(
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
    }

    function test_Deployment_FailsIf_QuoteTokenNotPoolToken() public {
        address notPoolToken = address(new ERC20Mock("", "", 18));
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert();
        new Aggor(
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
    }

    function test_Deployment_FailsIf_BaseTokenDecimalsWrong() public {
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert();
        new Aggor(
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
    }

    function test_Deployment_FailsIf_BaseTokenDecimalsBiggerThanMaxSupportedDecimals(
    ) public {
        uniswapBaseToken = address(new ERC20Mock("base", "base", 100)); // <- !
        uint8 decimals = IERC20(uniswapBaseToken).decimals();

        vm.expectRevert();
        new Aggor(
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
        uint valChr = val * 10 ** 18;
        uint valChl = val * 10 ** 8;

        // Let Chainlink's val have some % difference to Chronicles.
        // Note to keep vals in agreement distance.
        diff = _bound(diff, 0, agreementDistance);
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
        uint wantVal = ((valChr / 10 ** 10) + valChl) / 2;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 2, goodOracleCtr: 2});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function testFuzz_read_ChronicleOk_ChainlinkOk_NotInAgreementDistance_TwapOk(
        uint128 val,
        uint diff,
        bool diffDirection
    ) public {
        vm.assume(val != 0);
        vm.assume(val < type(uint128).max / 10 ** 18);

        // Scale val to oracles' decimals.
        uint valChr = val * 10 ** 18;
        uint valChl = val * 10 ** 8;

        // Let Chainlink's val have some % difference bigger than agreement
        // distance to Chronicles.
        // Note to overestimate diff to account for rounding errors.
        diff = _bound(diff, agreementDistance * 2, 1e18 - 1);
        //diff = 2e17;//_bound(diff, 0, agreementDistance) + agreementDistance;
        valChl = diffDirection
            ? valChl + (valChl * diff) / 1e18
            : valChl - (valChl * diff) / 1e18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(
            int(uint(valChl)), block.timestamp
        );

        // Expect val is median(valChr, valChl, valTwap)
        // Note to scale Chronicle's val down to Chainlik's decimals.
        uint wantVal = LibMedian.median(
            uint128(valChr / 10 ** 10), uint128(valChl), uint128(valTwap)
        );

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 3, goodOracleCtr: 2});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    // TODO: testFuzz_read_ChronicleOk_ChainlinkOk_NotInAgreementDistance_TwapNotOk
    function testFuzz_read_ChronicleOk_ChainlinkOk_NotInAgreementDistance_TwapNotOk(
        uint128 price,
        uint diff,
        uint diffDirection
    ) public {
        revert("NotImplemented");
    }

    function testFuzz_read_ChronicleOk_ChainlinkNotOk_ValNegative(
        uint128 valChr,
        int valChl
    ) public {
        vm.assume(valChr != 0);
        vm.assume(valChr < type(uint128).max / 10 ** 18);
        vm.assume(valChl < 0);

        // Scale Chronicle's val to 18 decimals.
        valChr *= 10 ** 18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(int(valChl), block.timestamp);

        // Expect only Chronicle's val, scaled down to 8 decimals.
        uint wantVal = uint(valChr) / 10 ** 10;

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
        vm.assume(valChr < type(uint128).max / 10 ** 18);
        vm.assume(uint(valChl) > type(uint128).max);

        // Scale Chronicle's val to 18 decimals.
        valChr *= 10 ** 18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        ChainlinkMock(chainlink).setValAndAge(int(valChl), block.timestamp);

        // Expect only Chronicle's val, scaled down to 8 decimals.
        uint wantVal = uint(valChr) / 10 ** 10;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
    }

    function testFuzz_read_ChronicleOk_ChainlinkNotOk_ValStale(
        uint128 valChr,
        uint128 valChl
    ) public {
        vm.assume(valChr != 0);
        vm.assume(valChr < type(uint128).max / 10 ** 18);

        // Scale Chronicle's val to 18 decimals.
        valChr *= 10 ** 18;

        // Set vals.
        ChronicleMock(chronicle).setValAndAge(valChr, block.timestamp);
        // Note to use stale timestamp.
        ChainlinkMock(chainlink).setValAndAge(int(uint(valChl)), 0);

        // Expect only Chronicle's val, scaled down to 8 decimals.
        uint wantVal = uint(valChr) / 10 ** 10;

        uint wantAge = block.timestamp;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});
        _checkReadFunctions(wantVal, wantAge, wantStatus);
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

    function testFuzz_ChronicleNotOk_ChainlinkOk_ValStale(
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

    function testFuzz_ChronicleNotOk_ChainlinkNotOk_TwapOk() public {
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

    // TODO: testFuzz_ChronicleNotOk_ChainlinkNotOk_TwapNotOk
    function testFuzz_ChronicleNotOk_ChainlinkNotOk_TwapNotOk() public {
        revert("NotImplemented");

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

    // -- Internal Helpers --

    function _setTwapNotOk() public {
        // See mocks/UniswapPoolMock::oberseve().
        UniswapPoolMock(uniswapPool).setShouldOverflowUint128(true);
    }
}
