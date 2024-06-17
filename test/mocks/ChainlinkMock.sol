// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract ChainlinkMock {
    int val;
    uint age;
    bool burnGas = false;

    function setValAndAge(int val_, uint age_) public {
        val = val_;
        age = age_;
    }

    function setBurnGas(bool burnGas_) public {
        burnGas = burnGas_;
    }

    function latestRoundData()
        public
        view
        returns (uint80, int, uint, uint, int80)
    {
        if (burnGas) {
            // Allocate "infinite" amount of memory.
            assembly ("memory-safe") {
                mstore(not(0), 1)
            }
        }

        return (0, val, 0, age, 0);
    }
}
