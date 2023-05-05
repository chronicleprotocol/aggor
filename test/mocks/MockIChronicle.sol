// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {IChronicle} from "src/interfaces/_external/IChronicle.sol";

contract MockIChronicle is IChronicle {
    bytes32 public wat;

    uint internal _val;
    uint internal _age;

    function setWat(bytes32 wat_) external {
        wat = wat_;
    }

    function setVal(uint val) external {
        _val = val;
    }

    function setAge(uint age) external {
        _age = age;
    }

    // -- IChronicle Functionality --

    function tryRead() external view returns (bool, uint) {
        return (_val != 0, _val);
    }

    function read() external view returns (uint) {
        require(_val != 0);

        return _val;
    }

    function readWithAge() external view returns (uint, uint) {
        require(_val != 0);
        return (_val, _age);
    }

    function tryReadWithAge() external view returns (bool, uint, uint) {
        return (_val != 0, _val, _age);
    }
}
