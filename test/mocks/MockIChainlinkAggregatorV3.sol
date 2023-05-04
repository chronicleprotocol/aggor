// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChainlinkAggregatorV3} from
    "src/interfaces/_external/IChainlinkAggregatorV3.sol";

contract MockIChainlinkAggregatorV3 is IChainlinkAggregatorV3 {
    bool private _shouldFail;
    int private _answer;
    uint private _updatedAt;
    uint8 private _decimals = 18;

    function setShouldFail(bool shouldFail) external {
        _shouldFail = shouldFail;
    }

    function setAnswer(int answer) external {
        _answer = answer;
    }

    function setUpdatedAt(uint updatedAt) external {
        _updatedAt = updatedAt;
    }

    function setDecimals(uint8 decimals_) external {
        _decimals = decimals_;
    }

    // -- IChainlinkAggregatorV3 Functionality --

    function latestRoundData()
        external
        view
        returns (uint80, int, uint, uint, uint80)
    {
        require(!_shouldFail);

        return (0, _answer, 0, _updatedAt, 0);
    }

    function latestAnswer() external view returns (int) {
        require(!_shouldFail);

        return _answer;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
