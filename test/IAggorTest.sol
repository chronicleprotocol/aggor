// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IAggor} from "src/IAggor.sol";

import {MockIChronicle} from "./mocks/MockIChronicle.sol";
import {MockIChainlinkAggregatorV3} from
    "./mocks/MockIChainlinkAggregatorV3.sol";

abstract contract IAggorTest is Test {
    IAggor aggor;

    MockIChronicle chronicle;
    MockIChainlinkAggregatorV3 chainlink;

    event StalenessThresholdUpdated(
        address indexed caller,
        uint oldStalenessThreshold,
        uint newStalenessThreshold
    );
    event SpreadUpdated(address indexed caller, uint oldSpread, uint newSpread);
    event ChainlinkValueStale(uint age, uint timestamp);
    event ChainlinkValueNegative(int value);
    event ChainlinkValueZero();

    function setUp(IAggor aggor_) internal {
        aggor = aggor_;

        chronicle = MockIChronicle(aggor.chronicle());
        chainlink = MockIChainlinkAggregatorV3(aggor.chainlink());

        // Toll address(this).
        IToll(address(aggor)).kiss(address(this));
    }

    // Copied from Aggor.sol
    uint internal constant _pscale = 10_000;

    function _pctdiff(uint a, uint b) private pure returns (uint) {
        if (a == b) return 0;
        return a > b
            ? _pscale - (((b * 1e18) / a) * _pscale / 1e18)
            : _pscale - (((a * 1e18) / b) * _pscale / 1e18);
    }

    function _distance(uint a, uint b) private pure returns (uint) {
        unchecked {
            return (a > b) ? a - b : b - a;
        }
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

        // IChainlink::decimals() set.
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

        uint32 age = uint32(block.timestamp);
        age++; // Note to use variable before warp as --via-ir optimization may
        age--; // optimize it away. solc doesn't know about vm.warp().

        chronicle.setVal(chronicleVal);

        chainlink.setAnswer(int(uint(chainlinkVal)));
        chainlink.setUpdatedAt(chainlinkAge);

        aggor.poke();

        // Wait for some time.
        vm.warp(block.timestamp + warp);

        (, uint curr) = aggor.tryRead();
        uint mean;
        uint pof = _pctdiff(chainlinkVal, chronicleVal);
        if (pof > 0 && pof > aggor.spread()) {
            mean = _distance(curr, chronicleVal) < _distance(curr, chainlinkVal)
                ? chronicleVal
                : chainlinkVal;
        } else {
            mean = (uint(chronicleVal) + uint(chainlinkVal)) / 2;
        }
        _checkReadFunctions({wantVal: uint128(mean), wantAge: age});
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
        aggor.setSpread(_pscale);

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

    // -- IChronicle Read Functionality --

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

    // -- Auth'ed Functionality --

    function testFuzz_setStalenessThreshold(uint stalenessThreshold) public {
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

    function testFuzz_setSpread(uint spread) public {
        vm.assume(spread <= _pscale);

        if (aggor.spread() != spread) {
            vm.expectEmit();
            emit SpreadUpdated(address(this), aggor.spread(), spread);
        }

        aggor.setSpread(spread);
        assertEq(aggor.spread(), spread);
    }

    function testFuzz_setSpread_FailsIf_IsBiggerThanPScal(uint spread) public {
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

    // -- Private Helpers --

    function _setValAndAge(uint val, uint age) private {
        require(
            val <= uint(type(int).max),
            "IAggorTest::_setValAndAge: val overflows int"
        );

        chronicle.setVal(val);

        chainlink.setAnswer(int(val));
        chainlink.setUpdatedAt(age);
        chainlink.setShouldFail(false);

        aggor.poke();
    }
}
