// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract ChainlinkMock_NoReturnData {
    function latestRoundData()
        public
        pure
        returns (uint80, int, uint, uint, int80)
    {
        assembly ("memory-safe") {
            return(0, 0)
        }
    }
}
