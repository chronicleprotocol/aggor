// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockIERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_, decimals_)
    {}

    function mint(address to, uint amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint amount) external {
        _burn(from, amount);
    }
}
