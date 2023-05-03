// NOTE: Run test/goerli.sh

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {OracleAggregator} from "src/OracleAggregator.sol";

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";
import {IChainlinkAggregator} from "src/interfaces/_external/IChainlinkAggregator.sol";

contract OracleAggregatorTest is Test {
    OracleAggregator oracle;

    function setUp() public {
        oracle = new OracleAggregator(
            // https://goerli.etherscan.io/address/0x56765C803a52a8fd4B26B3da8FF76D21fF9cB3E4#code
            0x56765C803a52a8fd4B26B3da8FF76D21fF9cB3E4,  
            // https://goerli.etherscan.io/address/0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e#code
            0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e
        );
        oracle.setStalenessThreshold(1 hours);
    }

    function test_valueReadOnchain() public {
        oracle.poke();
        (uint got, bool ok) = oracle.valueRead();
        emit log("Returned (mean) value:");
        emit log_uint(got);
        emit log("Returned ok?");
        emit log_uint(ok ? 1 : 0);
    }
}
