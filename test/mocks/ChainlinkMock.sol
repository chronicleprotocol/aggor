// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract ChainlinkMock {
    int val;
    uint age;

    function setValAndAge(int val_, uint age_) public {
        val = val_;
        age = age_;
    }

    function latestRoundData()
        public
        view
        returns (uint80, int, uint, uint, int80)
    {
        return (0, val, 0, age, 0);
    }
}
