// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";
import {IChronicle} from "chronicle-std/IChronicle.sol";

import {MockIChronicle} from "./mocks/MockIChronicle.sol";
import {LibCalc} from "src/libs/LibCalc.sol";

// -- Aggor Tests --

import {Aggor} from "src/Aggor.sol";

contract AggorTest is Test {
    Aggor aggor;
    Aggor aggorPegged;

    address[] public oracles;
    address public twap;
    bytes32 wat = "ETH/USD";

    function setUp() public {
        oracles.push(address(new MockIChronicle())); // I.e. Chronicle
        oracles.push(address(new MockIChronicle())); //      Chainlink
        twap = address(new MockIChronicle());

        aggor = new Aggor(address(this), wat, oracles, twap, 1 hours, false);

        aggorPegged =
            new Aggor(address(this), wat, oracles, twap, 1 hours, true);

        IToll(address(aggor)).kiss(address(this));
        IToll(address(aggorPegged)).kiss(address(this));
    }

    function test_Deployment() public {
        // Deployer is auth'ed.
        assertTrue(IAuth(address(aggor)).authed(address(this)));
        assertTrue(IAuth(address(aggorPegged)).authed(address(this)));

        // Oracles set.
        assertTrue(aggor.oracles().length == 2);
        assertTrue(aggor.oracles()[0] != address(0));
        assertTrue(aggor.oracles()[1] != address(0));

        assertFalse(aggor.isPeggedAsset());
        assertTrue(aggorPegged.isPeggedAsset());

        assertEq(aggor.decimals(), uint8(18));

        // No value set after deploy.
        (bool ok, uint val, uint age) = aggor.tryReadWithAge();
        assertFalse(ok);
        assertEq(val, 0);
        assertEq(age, 0);

        Aggor.StatusInfo memory status;
        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 6);
    }

    function test_setOracles() public {
        assertTrue(aggor.oracles().length == 2);
        oracles.push(address(new MockIChronicle()));
        aggor.setOracles(oracles);
        assertTrue(aggor.oracles().length == 3);
        assertEq(aggor.oracles()[0], oracles[0]);
        assertEq(aggor.oracles()[2], oracles[2]);
    }

    function test_setAgreementDistance() public {
        assertEq(aggor.agreementDistance(), 0);
        aggor.setAgreementDistance(500); // 5%
        assertEq(aggor.agreementDistance(), 500);
    }

    function test_setAcceptableAgeThreshold() public {
        assertEq(aggor.acceptableAgeThreshold(), 1 hours);
        aggor.setAcceptableAgeThreshold(5 minutes);
        assertEq(aggor.acceptableAgeThreshold(), 5 minutes);
    }

    // i.e. Happy path
    function test_Oracles_3orMore() public {
        oracles.push(address(new MockIChronicle()));

        MockIChronicle(oracles[0]).setVal(1 ether);
        MockIChronicle(oracles[1]).setVal(uint(1 ether) + 1);
        MockIChronicle(oracles[2]).setVal(uint(1 ether) + 2);

        uint ts = block.timestamp;
        uint ts1 = ts - 10;
        uint ts2 = ts - 20;
        MockIChronicle(oracles[0]).setAge(ts1);
        MockIChronicle(oracles[1]).setAge(ts2);
        MockIChronicle(oracles[2]).setAge(ts);

        aggor.setOracles(oracles);

        bool ok;
        uint val;
        uint age;

        (ok, val, age) = aggor.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, uint(1 ether) + 1); // Median
        assertEq(age, ts2);

        Aggor.StatusInfo memory status;
        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 1);

        // Add fourth Oracle
        oracles.push(address(new MockIChronicle()));
        MockIChronicle(oracles[3]).setVal(uint(1 ether) - 50);
        MockIChronicle(oracles[3]).setAge(ts - 99);
        aggor.setOracles(oracles);

        (ok, val, age) = aggor.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, 1 ether);
        assertEq(age, ts1);

        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 1);

        // Fourth Oracle returns bad age (too old), but we still
        // have enough prices for median. Note, this implicitly tests
        // acceptableAgeThreshold.

        MockIChronicle(oracles[3]).setVal(uint(1 ether) - 50);
        MockIChronicle(oracles[3]).setAge(ts - (ts / 2));
        (val, age, status) = aggor.readWithStatus();
        assertEq(val, uint(1 ether) + 1);
        assertEq(age, ts2);
        assertEq(status.returnLevel, 1);
        assertEq(status.countGoodOraclePrices, 3);
    }

    function test_Oracles_2PricesAgree() public {
        uint agreementDistance = 3333; // 33.33%
        aggor.setAgreementDistance(agreementDistance);

        uint price1 = uint(1.2 ether);
        uint price2 = uint(1.6 ether);
        MockIChronicle(oracles[0]).setVal(price1);
        MockIChronicle(oracles[1]).setVal(price2);
        MockIChronicle(oracles[0]).setAge(block.timestamp);
        MockIChronicle(oracles[1]).setAge(block.timestamp);

        bool ok;
        uint val;
        (ok, val) = aggor.tryRead();

        // We expect the price to be the mean of the two good prices
        assertEq((price1 + price2) / 2, val);

        Aggor.StatusInfo memory status;
        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 2);
    }

    function test_Oracles_2PricesDisagree() public {
        aggor.setAgreementDistance(3333); // 33.33%

        uint price1 = uint(1 ether);
        uint price2 = uint(1.5 ether);

        MockIChronicle(oracles[0]).setVal(price1);
        MockIChronicle(oracles[1]).setVal(price2);

        MockIChronicle(oracles[0]).setAge(block.timestamp);
        MockIChronicle(oracles[1]).setAge(block.timestamp);

        MockIChronicle(twap).setAge(block.timestamp);
        MockIChronicle(twap).setVal(0.9 ether);

        (bool ok, uint val) = aggor.tryRead();
        assertTrue(ok);

        // Price will be median of Oracles and TWAP
        assertEq(val, price1);

        Aggor.StatusInfo memory status;
        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 3);
    }

    function test_Oracles_1GoodPrice() public {
        oracles.push(address(new MockIChronicle()));

        MockIChronicle(oracles[0]).setVal(0);
        MockIChronicle(oracles[1]).setVal(1 ether);
        MockIChronicle(oracles[2]).setVal(1 ether);

        MockIChronicle(oracles[0]).setAge(block.timestamp);
        MockIChronicle(oracles[1]).setAge(block.timestamp);
        MockIChronicle(oracles[2]).setAge(0); // Bad age

        (bool ok, uint val, uint age) = aggor.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, 1 ether);
        assertEq(age, block.timestamp);

        Aggor.StatusInfo memory status;
        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 4);
    }

    function test_TWAPOnly() public {
        MockIChronicle(oracles[0]).setVal(0); // Bad price
        MockIChronicle(oracles[1]).setVal(1 ether);

        MockIChronicle(oracles[1]).setAge(block.timestamp);
        MockIChronicle(oracles[1]).setAge(0); // Bad age

        MockIChronicle(twap).setAge(block.timestamp - 1);
        MockIChronicle(twap).setVal(uint(1 ether) - 1);

        (bool ok, uint val, uint age) = aggor.tryReadWithAge();
        assertTrue(ok);
        assertEq(val, uint(1 ether) - 1);
        assertEq(age, block.timestamp - 1);

        Aggor.StatusInfo memory status;
        (,, status) = aggor.readWithStatus();
        assertEq(status.returnLevel, 5);
    }

    function test_Oracles_AgeInFuture() public {
        oracles.push(address(new MockIChronicle()));
        aggor.setOracles(oracles);
        aggor.setAgreementDistance(uint(1 ether) + 1);

        MockIChronicle(oracles[0]).setVal(1 ether);
        MockIChronicle(oracles[1]).setVal(uint(1 ether) * 2);
        MockIChronicle(oracles[2]).setVal(1 ether);

        MockIChronicle(oracles[0]).setAge(block.timestamp - 1);
        MockIChronicle(oracles[1]).setAge(block.timestamp);
        MockIChronicle(oracles[2]).setAge(block.timestamp + 1000);

        (uint val, uint age, Aggor.StatusInfo memory status) =
            aggor.readWithStatus();

        assertEq(val, (uint(1 ether) * 3) / 2);
        // Note on two Oracles (mean) within the agreement distance, we choose
        // the first oracle's age.
        assertEq(age, block.timestamp - 1);

        assertEq(status.returnLevel, 2);
        assertEq(status.countGoodOraclePrices, 2);
        assertEq(status.countFailedOraclePrices, 1);
    }

    function test_BigFailure() public {
        oracles.push(address(new MockIChronicle()));
        oracles.push(address(new MockIChronicle()));
        oracles.push(address(new MockIChronicle()));
        aggor.setOracles(oracles);
        aggor.setAgreementDistance(1001);

        MockIChronicle(oracles[0]).setVal(1 ether);
        MockIChronicle(oracles[1]).setVal(0); // Bad price
        MockIChronicle(oracles[2]).setVal(0); // Bad price
        MockIChronicle(oracles[3]).setVal(1 ether);
        MockIChronicle(oracles[4]).setVal(1 ether);

        MockIChronicle(oracles[0]).setAge(0); // Stale
        MockIChronicle(oracles[1]).setAge(block.timestamp);
        MockIChronicle(oracles[2]).setAge(block.timestamp);
        MockIChronicle(oracles[3]).setAge(block.timestamp + 1000); // Future
        MockIChronicle(oracles[4]).setAge(block.timestamp + 1); // Future

        MockIChronicle(twap).setAge(0);
        MockIChronicle(twap).setVal(1 ether);

        (uint val, uint age, Aggor.StatusInfo memory status) =
            aggor.readWithStatus();

        assertEq(val, 0);
        assertEq(age, 0);

        assertEq(status.returnLevel, 6);
        assertEq(status.countFailedOraclePrices, 5);
        assertFalse(status.twapUsed);
    }

    function test_AllReads() public {
        oracles.push(address(new MockIChronicle()));
        aggor.setOracles(oracles);

        MockIChronicle(oracles[0]).setVal(1 ether);
        MockIChronicle(oracles[1]).setVal(2 ether);
        MockIChronicle(oracles[2]).setVal(3 ether);
        MockIChronicle(oracles[0]).setAge(block.timestamp);
        MockIChronicle(oracles[1]).setAge(block.timestamp);
        MockIChronicle(oracles[2]).setAge(block.timestamp);

        uint val;
        uint valCmp;

        // Success

        val = aggor.read();
        assertEq(val, 2 ether);

        (, valCmp) = aggor.tryRead();
        assertEq(val, valCmp);

        (valCmp,) = aggor.readWithAge();
        assertEq(val, valCmp);

        (, valCmp,) = aggor.tryReadWithAge();
        assertEq(val, valCmp);

        (valCmp,,) = aggor.readWithStatus();
        assertEq(val, valCmp);

        int answer;
        (, answer,,,) = aggor.latestRoundData();
        assertEq(val, uint(answer));

        answer = aggor.latestAnswer();
        assertEq(LibCalc.scale(val, aggor.decimals(), 8), uint(answer));

        // Failure

        delete oracles;
        oracles.push(address(new MockIChronicle()));
        aggor.setOracles(oracles);

        (val,,) = aggor.readWithStatus();
        assertEq(val, 0);

        vm.expectRevert();
        val = aggor.read();

        (, valCmp) = aggor.tryRead();
        assertEq(val, valCmp);

        vm.expectRevert();
        (valCmp,) = aggor.readWithAge();

        (, valCmp,) = aggor.tryReadWithAge();
        assertEq(val, valCmp);

        (, answer,,,) = aggor.latestRoundData();
        assertEq(val, uint(answer));

        answer = aggor.latestAnswer();
        assertEq(LibCalc.scale(val, aggor.decimals(), 8), uint(answer));
    }

    function test_Pegged() public {
        oracles.push(address(new MockIChronicle()));
        aggorPegged.setOracles(oracles);

        aggorPegged.setAgreementDistance(500); // 5%

        // Prices above 1
        uint price1 = uint(1.05 ether);
        uint price2 = uint(1.15 ether);

        MockIChronicle(oracles[0]).setVal(price1);
        MockIChronicle(oracles[1]).setVal(0);
        MockIChronicle(oracles[2]).setVal(price2);
        MockIChronicle(oracles[0]).setAge(block.timestamp);
        MockIChronicle(oracles[1]).setAge(block.timestamp);
        MockIChronicle(oracles[2]).setAge(block.timestamp);

        uint val;

        val = aggorPegged.read();
        assertEq(val, price1);

        // Prices below 1
        price1 = uint(0.95 ether);
        price2 = uint(0.85 ether);
        MockIChronicle(oracles[0]).setVal(0);
        MockIChronicle(oracles[1]).setVal(price1);
        MockIChronicle(oracles[2]).setVal(price2);

        val = aggorPegged.read();
        assertEq(val, price1);

        // Prices disagree either side of 1
        price1 = uint(0.95 ether);
        price2 = uint(1.05 ether);
        MockIChronicle(oracles[0]).setVal(price2);
        MockIChronicle(oracles[1]).setVal(price1);
        MockIChronicle(oracles[2]).setVal(0);

        val = aggorPegged.read();
        assertEq(val, 1 ether);
    }
}

// -- Library Tests --

import {LibCalcTest as LibCalcTest_} from "./LibCalcTest.sol";

contract LibCalcTest is LibCalcTest_ {}
