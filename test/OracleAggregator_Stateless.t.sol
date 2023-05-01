// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {OracleAggregator_Stateless} from "src/OracleAggregator_Stateless.sol";

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";
import {IChainlinkAggregator} from "src/interfaces/_external/IChainlinkAggregator.sol";

contract OracleAggregator_StatelessTest is Test {
    OracleAggregator_Stateless oracle;

    Mock_ChainlinkAggregator chainlink = new Mock_ChainlinkAggregator(uint8(18));
    Mock_Chronicle chronicle = new Mock_Chronicle();

    function setUp() public {
        oracle = new OracleAggregator_Stateless();
    }

    function test_getData() public {
        chainlink.setAnswerAndUpdatedAt(10, block.timestamp);
        chronicle.setAnswer(20);

        OracleAggregator_Stateless.Oracle[] memory oracles = new OracleAggregator_Stateless.Oracle[](2);
        oracles[0] = OracleAggregator_Stateless.Oracle(address(chainlink), OracleAggregator_Stateless.Kind.Chainlink);
        oracles[1] = OracleAggregator_Stateless.Oracle(address(chronicle), OracleAggregator_Stateless.Kind.Chronicle);

        bytes[] memory args = new bytes[](1);
        args[0] = abi.encode(uint(1 hours));

        uint want = (10 + 20) / 2;
        (uint got, bool ok) = oracle.getData(oracles, 2, args);
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
