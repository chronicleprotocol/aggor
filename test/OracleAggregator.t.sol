// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {OracleAggregator} from "src/OracleAggregator.sol";

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";
import {IChainlinkAggregator} from "src/interfaces/_external/IChainlinkAggregator.sol";

contract OracleAggregatorTest is Test {
    OracleAggregator oracle;

    Mock_ChainlinkAggregator chainlink = new Mock_ChainlinkAggregator(uint8(18));
    Mock_Chronicle chronicle = new Mock_Chronicle();

    function setUp() public {
        oracle = new OracleAggregator(address(chronicle), address(chainlink));
        oracle.setStalenessThreshold(1 hours);
    }

    function test_valueRead() public {
        // IRL initial block timestamp will be much greter than whatever we set
        // for the staleness threshold
        vm.warp(oracle.stalenessThresholdSec()*2);

        chainlink.setAnswerAndUpdatedAt(10, block.timestamp);
        chronicle.setAnswer(20);

        // Never been poked
        (uint256 got, bool ok) = oracle.valueRead();
        assertEq(got, 0);
        assertEq(ok, false);

        oracle.poke();

        uint256 want = (10 + 20) / 2;
        (got, ok) = oracle.valueRead();
        assertEq(want, got);
        assertEq(ok, true);

        // Chronicle/Maker interface
        got = oracle.read();
        assertEq(want, got);

        // Chainlink deprecated interface
        int256 igot = oracle.latestAnswer();
        assertEq(want, uint256(igot));

        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(want, uint256(answer));
    }

    function test_lastGoodPrice() public {
        vm.warp(oracle.stalenessThresholdSec()*2);
        chronicle.setAnswer(20);
        chainlink.setAnswerAndUpdatedAt(10, block.timestamp);
        oracle.poke();

        uint256 want = (10 + 20) / 2;
        (uint256 got, bool ok) = oracle.valueRead();
        assertEq(want, got);
        assertEq(ok, true);

        vm.warp(oracle.stalenessThresholdSec()*3);
        chainlink.setAnswerAndUpdatedAt(20, block.timestamp); // i.e. (20+20)/2
        chronicle.setShouldFail(true);

        vm.expectRevert(abi.encodeWithSelector(OracleAggregator.ReportedPriceIsZero.selector, 20, 0));
        oracle.poke();

        (got, ok) = oracle.valueRead();
        assertEq(want, got);
        assertEq(ok, true);

        chronicle.setShouldFail(false);
        oracle.poke();

        vm.warp(oracle.stalenessThresholdSec()*4);

        // Update price
        want = (20 + 20) / 2;
        (got, ok) = oracle.valueRead();
        assertEq(want, got);
        assertEq(ok, true);

        chainlink.setAnswerAndUpdatedAt(30, block.timestamp - (oracle.stalenessThresholdSec() + 1));
        vm.expectRevert(abi.encodeWithSelector(OracleAggregator.ChainlinkStalePrice.selector, 10799, 3601));
        oracle.poke();

        // Price stays the same (last known good price)
        (got, ok) = oracle.valueRead();
        assertEq(want, got);
        assertEq(ok, true);
    }

    function test_Chainlink_DecimalConversion() public {
        chronicle.setAnswer(1e18);

        // Less than 18 decimals.
        chainlink = new Mock_ChainlinkAggregator(uint8(6));
        oracle = new OracleAggregator(address(chronicle), address(chainlink));

        chainlink.setAnswerAndUpdatedAt(1e6, block.timestamp); // 1
        oracle.poke();
        uint want = 1e18;
        (uint got, bool ok) = oracle.valueRead();
        assertTrue(ok);
        assertEq(want, got);

        // More than 18 decimals.
        chainlink = new Mock_ChainlinkAggregator(uint8(20));
        oracle = new OracleAggregator(address(chronicle), address(chainlink));

        chainlink.setAnswerAndUpdatedAt(1e20, block.timestamp); // 1
        oracle.poke();
        want = 1e18;
        (got, ok) = oracle.valueRead();
        assertTrue(ok);
        assertEq(want, got);
    }
}

contract Mock_ChainlinkAggregator is IChainlinkAggregator {
    uint8 public immutable decimals;

    int256 private _answer;
    uint256 private _updatedAt;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setAnswerAndUpdatedAt(int256 answer, uint256 updatedAt) external {
        _answer = answer;
        _updatedAt = updatedAt;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        answer = _answer;
        updatedAt = _updatedAt;
        roundId = uint80(block.timestamp % 9001);
        startedAt = 0;
        answeredInRound = uint80(block.timestamp % 1009);
    }
}

contract Mock_Chronicle is IChronicle {
    uint256 private _answer;
    bool private should_fail;

    function setAnswer(uint256 answer) external {
        _answer = answer;
    }

    function setShouldFail(bool should_fail_) external {
        should_fail = should_fail_;
    }

    function read() external view returns (uint256) {
        if (should_fail) {
            // https://github.com/chronicleprotocol/medianite/blob/master/deploy/arbitrum-ETHUSD/median/src/median.sol#L84
            revert("Median/invalid-price-feed");
        }

        return _answer;
    }
}
