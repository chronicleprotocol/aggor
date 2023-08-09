// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";

import {IAggor} from "src/IAggor.sol";
import {Aggor} from "src/Aggor.sol";

contract Aggor_COUNTER is Aggor {
    // @todo   ^ Adjust name of Aggor instance.
    constructor(
        address initialAuthed,
        address chronicle_,
        address chainlink_,
        address uniPool_,
        bool uniUseToken0AsBase
    )
        Aggor(initialAuthed, chronicle_, chainlink_, uniPool_, uniUseToken0AsBase)
    {}
}

/**
 * @notice Aggor Management Script
 */
contract AggorScript is Script {
    /// @dev Deploys a new Aggor instance via Greenhouse instance `greenhouse`
    ///      and salt `salt` with `initialAuthed` being the address initially
    ///      authed.
    ///
    ///      The other arguments are Aggor's additional constructor arguments.
    function deploy(
        address greenhouse,
        bytes32 salt,
        address initialAuthed,
        address chronicle,
        address chainlink,
        address uniPool,
        bool uniUseToken0AsBase
    ) public {
        // Create creation code with constructor arguments.
        bytes memory creationCode = abi.encodePacked(
            type(Aggor_COUNTER).creationCode,
            // @todo   ^ Adjust name of Aggor instance.
            abi.encode(
                initialAuthed, chronicle, chainlink, uniPool, uniUseToken0AsBase
            )
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        vm.startBroadcast();
        IGreenhouse(greenhouse).plant(salt, creationCode);
        vm.stopBroadcast();

        console2.log("Deployed at", deployed);
    }

    // -- IAggor Functions --

    /// @dev Pokes Aggor.
    function poke(address self) public {
        vm.startBroadcast();
        IAggor(self).poke();
        vm.stopBroadcast();

        console2.log("Poked");
    }

    /// @dev Sets staleness threshold to `stalenessThreshold`.
    function setStalenessThreshold(address self, uint32 stalenessThreshold)
        public
    {
        vm.startBroadcast();
        IAggor(self).setStalenessThreshold(stalenessThreshold);
        vm.stopBroadcast();

        console2.log("Staleness Threshold set to", stalenessThreshold);
    }

    /// @dev Sets spread to `spread`.
    function setSpread(address self, uint16 spread) public {
        vm.startBroadcast();
        IAggor(self).setSpread(spread);
        vm.stopBroadcast();

        console2.log("Spread set to", spread);
    }

    /// @dev Sets whether to use Uniswap's TWAP oracle or not.
    function useUniswap(address self, bool select) public {
        vm.startBroadcast();
        IAggor(self).useUniswap(select);
        vm.stopBroadcast();

        console2.log("Use Uniswap set to", select);
    }

    /// @dev Sets Uniswap TWAP's oracle lookback time in seconds.
    function setUniSecondsAgo(address self, uint32 uniSecondsAgo) public {
        vm.startBroadcast();
        IAggor(self).setUniSecondsAgo(uniSecondsAgo);
        vm.stopBroadcast();

        console2.log("Uniswap Seconds Ago set to", uniSecondsAgo);
    }

    // -- IAuth Functions --

    /// @dev Grants auth to address `who`.
    function rely(address self, address who) public {
        vm.startBroadcast();
        IAuth(self).rely(who);
        vm.stopBroadcast();

        console2.log("Relied", who);
    }

    /// @dev Renounces auth from address `who`.
    function deny(address self, address who) public {
        vm.startBroadcast();
        IAuth(self).deny(who);
        vm.stopBroadcast();

        console2.log("Denied", who);
    }

    // -- IToll Functions --

    /// @dev Grants toll to address `who`.
    function kiss(address self, address who) public {
        vm.startBroadcast();
        IToll(self).kiss(who);
        vm.stopBroadcast();

        console2.log("Kissed", who);
    }

    /// @dev Renounces toll from address `who`.
    function diss(address self, address who) public {
        vm.startBroadcast();
        IToll(self).diss(who);
        vm.stopBroadcast();

        console2.log("Dissed", who);
    }
}
