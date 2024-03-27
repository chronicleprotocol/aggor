// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract ChronicleMock {
    uint val;
    uint age;
    bool ok = true;
    bool tolled = true;

    function setValAndAge(uint val_, uint age_) public {
        val = val_;
        age = age_;
    }

    function setOk(bool ok_) public {
        ok = ok_;
    }

    function setTolled(bool tolled_) public {
        tolled = tolled_;
    }

    function tryReadWithAge() public view returns (bool, uint, uint) {
        require(tolled);

        return (ok, val, age);
    }
}
