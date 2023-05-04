// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";

contract MockIChronicle is IChronicle {
    uint private _val;

    function setVal(uint val) external {
        _val = val;
    }

    // -- IChronicle Functionality --

    function tryRead() external view returns (bool, uint) {
        return (_val != 0, _val);
    }

    function read() external view returns (uint) {
        require(_val != 0);

        return _val;
    }
}
