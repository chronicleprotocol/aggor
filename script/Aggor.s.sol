// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAggor} from "src/IAggor.sol";
import {Aggor} from "src/Aggor.sol";

/**
 * @title Aggor Management Script
 *
 * @dev Usage:
 *
 *      ```bash
 *      forge script \
 *          --broadcast \
 *          --rpc-url <RPC_URL> \
 *          --private-key <PRIVATE_KEY> \
 *          --etherscan-api-key <ETHERSCAN_API_KEY> \
 *          --verify
 *          --sig "deploy()"
 *          script/Aggor.s.sol:AggorScript
 *      ```
 */
contract AggorScript is Script {
    /// @dev You'll want to adjust this addresses before deployment.
    ///      Note that deployment fails if addresses are zero.
    address internal constant ORACLE_CHRONICLE = address(0);
    address internal constant ORACLE_CHAINLINK = address(0);
    address internal constant ORACLE_UNISWAP = address(0);

    /// @dev You'll want to adjust this address if Aggor is already deployed.
    IAggor internal aggor = IAggor(address(0));

    function deploy() public returns (IAggor) {
        vm.startBroadcast();
        aggor =
            new Aggor(ORACLE_CHRONICLE, ORACLE_CHAINLINK, ORACLE_UNISWAP, false);
        vm.stopBroadcast();

        return aggor;
    }
}
