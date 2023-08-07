// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IGreenhouse} from "greenhouse/src/IGreenhouse.sol";

import {IAggor} from "src/IAggor.sol";
import {Aggor} from "src/Aggor.sol";

contract Aggor_1 is Aggor {
    // @todo   ^ Adjust name of Aggor instance.
    constructor(
        address oracleChronicle,
        address oracleChainlink,
        address oracleUniswap,
        bool uniUseToken0AsBase,
        address initialAuthed
    )
        Aggor(
            oracleChronicle,
            oracleChainlink,
            oracleUniswap,
            uniUseToken0AsBase,
            initialAuthed
        )
    {}
}

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
 *          --sig $(cast calldata "deploy(address,bytes32,address,address,address,bool,address)" <...>)
 *          script/Aggor.s.sol:AggorScript
 *      ```
 */
contract AggorScript is Script {
    function deploy(
        address greenhouse,
        bytes32 salt,
        address oracleChronicle,
        address oracleChainlink,
        address oracleUniswap,
        bool uniUseToken0AsBase,
        address initialAuthed
    ) public {
        // Create creation code with constructor argument.
        bytes memory creationCode = abi.encodePacked(
            type(Aggor_1).creationCode,
            // @todo   ^ Adjust name of Aggor instance.
            abi.encode(oracleChronicle, oracleChainlink, oracleUniswap, uniUseToken0AsBase, initialAuthed)
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        vm.startBroadcast();
        IGreenhouse(greenhouse).plant(salt, creationCode);
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
    }
}
