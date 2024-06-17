// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

contract ChronicleMock {
    uint val;
    uint age;
    bool ok = true;
    bool tolled = true;
    bool burnGas = false;

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

    function setBurnGas(bool burnGas_) public {
        burnGas = burnGas_;
    }

    function tryReadWithAge() public view returns (bool, uint, uint) {
        require(tolled);

        if (burnGas) {
            // Allocate "infinite" amount of memory.
            assembly ("memory-safe") {
                mstore(not(0), 1)
            }
        }

        return (ok, val, age);
    }
}
