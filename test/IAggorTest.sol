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

    function test_Deployment() public {
        // Deployer is auth'ed.
        assertTrue(IAuth(address(aggor)).authed(address(this)));

        // Oracles set.
        assertTrue(address(aggor.chronicle()) != address(0));
        assertTrue(address(aggor.chainlink()) != address(0));

        // StalenessThreshold set.
        assertTrue(aggor.stalenessThreshold() != 0);

        // No value set.
        bool ok;
        uint val;
        (ok, val) = aggor.tryRead();
        assertFalse(ok);
        assertEq(val, 0);
    }

    // -- Poke --

    function _checkReadFunctions(uint128 wantVal, uint wantAge) private {
        bool ok;
        uint gotVal;

        // IChronicle::read
        gotVal = aggor.read();
        assertEq(gotVal, wantVal);

        // IChronicle::tryRead
        (ok, gotVal) = aggor.tryRead();
        assertTrue(ok);
        assertEq(gotVal, wantVal);

        // IChainlinkAggregatorV3::latestRoundData
        uint80 roundId;
        int answer;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;
        (roundId, answer, startedAt, updatedAt, answeredInRound) =
            aggor.latestRoundData();
        assertEq(roundId, 0);
        assertTrue(answer > 0);
        assertEq(uint128(uint(answer)), wantVal);
        assertEq(startedAt, 0);
        assertEq(updatedAt, wantAge);
        assertEq(answeredInRound, 0);

        // IChainlinkAggregatorV3::latestAnswer
        answer = aggor.latestAnswer();
        assertTrue(answer > 0);
        assertEq(uint128(uint(answer)), wantVal);
    }

    function test_poke(
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

        uint mean = (uint(chronicleVal) + uint(chainlinkVal)) / 2;
        _checkReadFunctions({wantVal: uint128(mean), wantAge: age});
    }

    function test_poke_FailsIf_ChronicleValueZero(uint128 val) public {
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

    function test_poke_FailsIf_ChainlinkValueZero(uint128 val) public {
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

    function test_poke_FailsIf_ChainlinkValueStale(
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

    function test_poke_FailsIf_ChainlinkValueNegative(
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

    // -- Auth'ed Functionality --

    function test_setStalenessThreshold(uint stalenessThreshold) public {
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