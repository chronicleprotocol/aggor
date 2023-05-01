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
        oracle.setChainlinkStalenessThreshold(1 hours);
    }

    function test_valueRead() public {
        chainlink.setAnswerAndUpdatedAt(10, block.timestamp);
        chronicle.setAnswer(20);

        uint256 want = (10 + 20) / 2;
        (uint256 got, bool ok) = oracle.valueRead();
        assertTrue(ok);
        assertEq(want, got);

        // Chronicle/Maker interface
        got = oracle.read();
        assertEq(want, got);

        // Chainlink deprecated interface
        int256 igot = oracle.latestAnswer();
        assertEq(want, uint256(igot));
    }
    /*
    function test_getData_Chronicle_RecoversRevert() public {
        chainlink.setAnswerAndUpdatedAt(10, block.timestamp);
        chronicle.setShouldFail(true);

        uint want = 10;
        (uint got, bool ok) = oracle.getData();
        assertFalse(ok);
        assertEq(want, got);
    }

    function test_getData_Chainlink_StalenessThresholdRespected() public {
        chainlink.setAnswerAndUpdatedAt(10, block.timestamp);
        chronicle.setAnswer(20);

        // Chainlink's threshold set to 1 hour.
        vm.warp(block.timestamp + 2 hours);

        uint want = 20; // Only chronicle oracle's value used
        (uint got, bool ok) = oracle.getData();
        assertFalse(ok); // min_oracle threshold not reached
        assertEq(want, got);
    }

    function test_getData_Chainlink_DecimalConversion() public {
        oracle.drop(address(chainlink));
        chronicle.setAnswer(1e18);

        // Less than 18 decimals.
        chainlink = new Mock_ChainlinkAggregator(uint8(6));
        oracle.lift(address(chainlink), OracleAggregator.Kind.Chainlink);

        chainlink.setAnswerAndUpdatedAt(1e6, block.timestamp); // 1
        uint want = 1e18;
        (uint got, bool ok) = oracle.getData();
        assertTrue(ok);
        assertEq(want, got);

        oracle.drop(address(chainlink));

        // More than 18 decimals.
        chainlink = new Mock_ChainlinkAggregator(uint8(20));
        oracle.lift(address(chainlink), OracleAggregator.Kind.Chainlink);

        chainlink.setAnswerAndUpdatedAt(1e20, block.timestamp); // 1
        want = 1e18;
        (got, ok) = oracle.getData();
        assertTrue(ok);
        assertEq(want, got);
    }
    */
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
            revert("");
        }

        return _answer;
    }
}
