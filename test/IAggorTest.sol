// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {LibCalc} from "src/libs/LibCalc.sol";
import {IAggor} from "src/IAggor.sol";

import {MockIChronicle} from "./mocks/MockIChronicle.sol";
import {MockIChainlinkAggregatorV3} from
    "./mocks/MockIChainlinkAggregatorV3.sol";
import {MockUniswapPool} from "./mocks/MockUniswapPool.sol";
import {MockIERC20} from "./mocks/MockIERC20.sol";

abstract contract IAggorTest is Test {
    IAggor aggor;

    MockIChronicle chronicle;
    MockIChainlinkAggregatorV3 chainlink;
    MockUniswapPool uniPool;
    MockIERC20 uniPoolToken0;
    MockIERC20 uniPoolToken1;

    /// @dev Must match the value in Aggor.sol
    uint16 internal constant _pscale = 10_000;

    // Copied from IAggor.
    event UniswapUpdated(
        address indexed caller, address oldUniswapPool, address newUniswapPool
    );
    event StalenessThresholdUpdated(
        address indexed caller,
        uint32 oldStalenessThreshold,
        uint32 newStalenessThreshold
    );
    event SpreadUpdated(
        address indexed caller, uint16 oldSpread, uint16 newSpread
    );
    event UniswapSecondsAgoUpdated(
        address indexed caller,
        uint32 oldUniswapSecondsAgo,
        uint32 newUniswapSecondsAgo
    );
    event ChronicleValueStale(uint age, uint timestamp);
    event ChainlinkValueStale(uint age, uint timestamp);
    event ChainlinkValueNegative(int value);
    event ChainlinkValueZero();

    function setUp(IAggor aggor_) internal {
        aggor = aggor_;

        chronicle = MockIChronicle(aggor.chronicle());
        chainlink = MockIChainlinkAggregatorV3(aggor.chainlink());

        uniPoolToken0 =
            new MockIERC20("Uniswap Pool Token 0", "UniToken0", uint8(18));
        uniPoolToken1 =
            new MockIERC20("Uniswap Pool Token 1", "UniToken1", uint8(18));
        uniPool =
            new MockUniswapPool(address(uniPoolToken0), address(uniPoolToken1));

        // Toll address(this).
        IToll(address(aggor)).kiss(address(this));
    }

    function test_Deployment() public {
        // Deployer is auth'ed.
        assertTrue(IAuth(address(aggor)).authed(address(this)));

        // Oracles set.
        assertTrue(address(aggor.chronicle()) != address(0));
        assertTrue(address(aggor.chainlink()) != address(0));

        // StalenessThreshold set.
        assertTrue(aggor.stalenessThreshold() != 0);

        // Spread set.
        assertTrue(aggor.spread() != 0);

        // UniSecondsAgo set.
        assertTrue(aggor.uniSecondsAgo() != 0);

        // IChainlinkAggregatorV3::decimals() set.
        assertEq(aggor.decimals(), uint8(18));

        // No value set.
        bool ok;
        uint val;
        (ok, val) = aggor.tryRead();
        assertFalse(ok);
        assertEq(val, 0);
    }

    // -- Poke --

    function _checkReadFunctions(uint128 wantVal, uint wantAge) private {
        // -- IChronicle
        bool ok;
        uint gotVal;
        uint gotAge;

        // IChronicle::read
        gotVal = aggor.read();
        assertEq(gotVal, wantVal);

        // IChronicle::tryRead
        (ok, gotVal) = aggor.tryRead();
        assertTrue(ok);
        assertEq(gotVal, wantVal);

        // IChronicle::readWithAge
        (gotVal, gotAge) = aggor.readWithAge();
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);

        // IChronicle::tryReadWithAge
        (ok, gotVal, gotAge) = aggor.tryReadWithAge();
        assertTrue(ok);
        assertEq(gotVal, wantVal);
        assertEq(gotAge, wantAge);

        // -- IChainlink
        uint80 roundId;
        int answer;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;

        // IChainlinkAggregatorV3::latestRoundData
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            aggor.latestRoundData();
        assertEq(roundId, 1);
        assertTrue(answer > 0);
        assertEq(uint128(uint(answer)), wantVal);
        assertEq(startedAt, 0);
        assertEq(updatedAt, wantAge);
        assertEq(answeredInRound, 1);

        // IChainlinkAggregatorV3::latestAnswer
        answer = aggor.latestAnswer();
        assertTrue(answer > 0);
        assertEq(uint128(uint(answer)), wantVal);
    }

    function testFuzz_poke_basic(
        uint128 chronicleVal,
        uint128 chainlinkVal,
        uint chainlinkAgeSeed,
        uint chronicleAgeSeed,
        uint warp
    ) public {
        vm.assume(chronicleVal != 0);
        vm.assume(chainlinkVal != 0);
        vm.assume(warp < 100 days); // Make sure to not overflow timestamp.

        // Make sure chainlink's age is not stale.
        uint32 chainlinkAge = uint32(
            bound(
                chainlinkAgeSeed,
                block.timestamp - aggor.stalenessThreshold(),
                block.timestamp
            )
        );

        // Make sure chronicle'a age is not stale.
        uint32 chronicleAge = uint32(
            bound(
                chronicleAgeSeed,
                block.timestamp - aggor.stalenessThreshold(),
                block.timestamp
            )
        );

        uint32 age = uint32(block.timestamp);
        age++; // Note to use variable before warp as --via-ir optimization may
        age--; // optimize it away. solc doesn't know about vm.warp().

        chronicle.setVal(chronicleVal);
        chronicle.setAge(chronicleAge);

        chainlink.setAnswer(int(uint(chainlinkVal)));
        chainlink.setUpdatedAt(chainlinkAge);

        aggor.poke();

        // Wait for some time.
        vm.warp(block.timestamp + warp);

        // Read aggor's value.
        bool ok;
        uint cur;
        (ok, cur) = aggor.tryRead();
        assertTrue(ok);
        assertNotEq(cur, 0);

        // Compute expected value.
        uint wantVal;

        uint diff = LibCalc.pctDiff(chainlinkVal, chronicleVal, _pscale);
        if (diff != 0 && diff > aggor.spread()) {
            // If difference of values is bigger than acceptable spread, the
            // expected value is the oracle's value with less difference to
            // aggor's previous value.j
            uint previousVal = 0;

            wantVal = LibCalc.distance(previousVal, chronicleVal)
                < LibCalc.distance(previousVal, chainlinkVal)
                ? chronicleVal
                : chainlinkVal;
        } else {
            // If difference of values is less then acceptable spread, the
            // expected value is the mean of the values.
            // Note that the mean of two values is their average.
            wantVal = (uint(chronicleVal) + uint(chainlinkVal)) / 2;
        }

        _checkReadFunctions({wantVal: uint128(wantVal), wantAge: age});
    }

    function testFuzz_poke_FailsIf_ChronicleValueZero(uint128 val) public {
        vm.assume(val != 0);
        _setValAndAge(val, uint32(block.timestamp));

        // Let chronicle's val to zero.
        chronicle.setVal(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAggor.OracleReadFailed.selector, address(chronicle)
            )
        );
        aggor.poke();
    }

    function testFuzz_poke_FailsIf_ChronicleValueStale(
        uint128 val,
        uint chronicleAgeSeed
    ) public {
        vm.assume(val != 0);
        _setValAndAge(val, uint32(block.timestamp));

        // Let chronicle's age be stale.
        uint chronicleAge = bound(
            chronicleAgeSeed,
            0,
            block.timestamp - aggor.stalenessThreshold() - 1
        );
        chronicle.setAge(chronicleAge);

        vm.expectEmit();
        emit ChronicleValueStale(chronicleAge, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAggor.OracleReadFailed.selector, address(chronicle)
            )
        );
        aggor.poke();
    }

    function testFuzz_poke_FailsIf_ChainlinkValueZero(uint128 val) public {
        vm.assume(val != 0);
        _setValAndAge(val, uint32(block.timestamp));

        // Let chainlink's val be zero.
        chainlink.setAnswer(0);

        vm.expectEmit();
        emit ChainlinkValueZero();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAggor.OracleReadFailed.selector, address(chainlink)
            )
        );
        aggor.poke();
    }

    function testFuzz_poke_FailsIf_ChainlinkValueStale(
        uint128 val,
        uint chainlinkAgeSeed
    ) public {
        vm.assume(val != 0);
        _setValAndAge(val, uint32(block.timestamp));

        // Let chainlink's age be stale.
        uint chainlinkAge = bound(
            chainlinkAgeSeed,
            0,
            block.timestamp - aggor.stalenessThreshold() - 1
        );
        chainlink.setUpdatedAt(chainlinkAge);

        vm.expectEmit();
        emit ChainlinkValueStale(chainlinkAge, block.timestamp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAggor.OracleReadFailed.selector, address(chainlink)
            )
        );
        aggor.poke();
    }

    function testFuzz_poke_FailsIf_ChainlinkValueNegative(
        uint128 val,
        int chainlinkValSeed
    ) public {
        vm.assume(val != 0);
        _setValAndAge(val, uint32(block.timestamp));

        // Let chainlink's val be negative.
        int chainlinkVal = bound(chainlinkValSeed, type(int).min, -1);
        chainlink.setAnswer(chainlinkVal);

        vm.expectEmit();
        emit ChainlinkValueNegative(chainlinkVal);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAggor.OracleReadFailed.selector, address(chainlink)
            )
        );
        aggor.poke();
    }

    function test_poke_ChainlinkDecimalConversion() public {
        uint want;
        uint val;
        aggor.setSpread(uint16(_pscale));

        // Case 1: chainlink.decimals < 18.
        _setValAndAge(10e17, block.timestamp);
        chainlink.setDecimals(17);
        aggor.poke();

        want = 55e17; // = 5.5e18 => (1 + 10) / 2 = 5.5
        val = aggor.read();

        assertEq(val, want);

        // Case 2: chainlink.decimals > 18.
        _setValAndAge(1e19, block.timestamp);
        chainlink.setDecimals(19);
        aggor.poke();

        want = 55e17; // = 5.5e18 => (10 + 1) / 2 = 5.5
        val = aggor.read();

        assertEq(val, want);
    }

    function test_pause() public {
        _setValAndAge(1000, block.timestamp);
        assertEq(aggor.read(), 1000);

        aggor.pause(true);
        _setValAndAge(9000, block.timestamp);
        assertTrue(aggor.paused());
        assertEq(aggor.read(), 1000); // Price unchanged after poke

        aggor.pause(false);
        _setValAndAge(9000, block.timestamp);
        assertTrue(!aggor.paused());
        assertEq(aggor.read(), 9000);
    }

    // -- Read Functionality --

    // -- IChronicle

    function test_read_FailsIfValIsZero() public {
        vm.expectRevert();
        aggor.read();
    }

    function test_tryRead_ReturnsFalseIfValIsZero() public {
        bool ok;
        (ok,) = aggor.tryRead();
        assertFalse(ok);
    }

    function test_readWithAge_FailsIfValIsZero() public {
        vm.expectRevert();
        aggor.readWithAge();
    }

    function test_tryReadWithAge_ReturnsFalseIfValIsZero() public {
        bool ok;
        (ok,,) = aggor.tryReadWithAge();
        assertFalse(ok);
    }

    // -- Toll Protection

    function test_read_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.read();
    }

    function test_tryRead_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.tryRead();
    }

    function test_readWithAge_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.readWithAge();
    }

    function test_tryReadWithAge_IsTollProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(IToll.NotTolled.selector, address(0xbeef))
        );
        aggor.tryReadWithAge();
    }

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

    // -- Auth'ed Functionality --

    function testFuzz_setStalenessThreshold(uint32 stalenessThreshold) public {
        vm.assume(stalenessThreshold != 0);

        if (aggor.stalenessThreshold() != stalenessThreshold) {
            vm.expectEmit();
            emit StalenessThresholdUpdated(
                address(this), aggor.stalenessThreshold(), stalenessThreshold
            );
        }

        aggor.setStalenessThreshold(stalenessThreshold);
        assertEq(aggor.stalenessThreshold(), stalenessThreshold);
    }

    function test_setStalenessThreshold_FailsIf_IsZero() public {
        vm.expectRevert();
        aggor.setStalenessThreshold(0);
    }

    function test_setStalenessThreshold_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.setStalenessThreshold(1);
    }

    function testFuzz_setSpread(uint16 spread) public {
        vm.assume(spread <= _pscale);

        if (aggor.spread() != spread) {
            vm.expectEmit();
            emit SpreadUpdated(address(this), aggor.spread(), spread);
        }

        aggor.setSpread(spread);
        assertEq(aggor.spread(), spread);
    }

    function testFuzz_setSpread_FailsIf_BiggerThanPScale(uint16 spread)
        public
    {
        vm.assume(spread > _pscale);

        vm.expectRevert();
        aggor.setSpread(spread);
    }

    function test_setSpread_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.setSpread(1);
    }

    function testFuzz_setUniSecondsAgo(uint32 uniSecondsAgo) public {
        vm.assume(uniSecondsAgo >= aggor.minUniSecondsAgo());

        if (aggor.uniSecondsAgo() != uniSecondsAgo) {
            vm.expectEmit();
            emit UniswapSecondsAgoUpdated(
                address(this), aggor.uniSecondsAgo(), uniSecondsAgo
            );
        }

        aggor.setUniSecondsAgo(uniSecondsAgo);
        assertEq(aggor.uniSecondsAgo(), uniSecondsAgo);
    }

    function testFuzz_setUniSecondsAgo_FailsIf_LessThanMinAllowedSeconds(
        uint32 uniSecondsAgo
    ) public {
        vm.assume(uniSecondsAgo < aggor.minUniSecondsAgo());

        vm.expectRevert();
        aggor.setUniSecondsAgo(uniSecondsAgo);
    }

    function test_setUniSecondsAgo_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.setUniSecondsAgo(1);
    }

    function test_setUniswap_FromZeroAddress() public {
        vm.expectEmit();
        emit UniswapUpdated(address(this), address(0), address(uniPool));

        aggor.setUniswap(address(uniPool));

        assertEq(aggor.uniPool(), address(uniPool));
        assertEq(aggor.uniBasePair(), address(uniPoolToken0));
        assertEq(aggor.uniQuotePair(), address(uniPoolToken1));
        assertEq(aggor.uniBaseDec(), uint8(18));
        assertEq(aggor.uniQuoteDec(), uint8(18));
    }

    function test_setUniswap_ToZeroAddress() public {
        aggor.setUniswap(address(uniPool));

        vm.expectEmit();
        emit UniswapUpdated(address(this), address(uniPool), address(0));

        aggor.setUniswap(address(0));

        assertEq(aggor.uniPool(), address(0));
        assertEq(aggor.uniBasePair(), address(0));
        assertEq(aggor.uniQuotePair(), address(0));
        assertEq(aggor.uniBaseDec(), uint8(0));
        assertEq(aggor.uniQuoteDec(), uint8(0));
    }

    function test_setUniswap_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.setUniswap(address(0));
    }

    function test_Pause_IsAuthProtected() public {
        vm.prank(address(0xbeef));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuth.NotAuthorized.selector, address(0xbeef)
            )
        );
        aggor.pause(true);
    }

    // -- Private Helpers --

    function _setValAndAge(uint val, uint age) private {
        require(
            val <= uint(type(int).max),
            "IAggorTest::_setValAndAge: val overflows int"
        );

        chronicle.setVal(val);
        chronicle.setAge(age);

        chainlink.setAnswer(int(val));
        chainlink.setUpdatedAt(age);
        chainlink.setShouldFail(false);

        aggor.poke();
    }
}
