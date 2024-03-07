// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";

import {IAggor} from "src/IAggor.sol";
import {Aggor_BASE_QUOTE_COUNTER as Aggor} from "src/Aggor.sol";
// @todo      ^^^^ ^^^^^ ^^^^^^^ Adjust name of Aggor instance

/**
 * @notice Aggor Management Script
 */
contract AggorScript is Script {
    // -- Deployment Configuration --

    // -- Immutable

    address chronicle;
    address chainlink;
    address uniswapPool;
    address uniswapBaseToken;
    address uniswapQuoteToken;
    uint8 uniswapBaseTokenDecimals;
    uint32 uniswapLookback;

    // -- Mutable

    uint128 agreementDistance;
    uint32 ageThreshold;

    // -- Deployment Function --

    /// @dev Deploys a new Aggor instance via Greenhouse instance
    ///      `greenhouse` and salt `salt` with `initialAuthed` being the
    ///      address initially auth'ed.
    function deploy(address greenhouse, bytes32 salt, address initialAuthed)
        public
    {
        // Create creation code with constructor arguments.
        bytes memory creationCode = abi.encodePacked(
            type(Aggor).creationCode,
            abi.encode(
                initialAuthed,
                chronicle,
                chainlink,
                uniswapPool,
                uniswapBaseToken,
                uniswapQuoteToken,
                uniswapBaseTokenDecimals,
                uniswapLookback,
                agreementDistance,
                ageThreshold
            )
        );

        // Ensure salt not yet used.
        address deployed = IGreenhouse(greenhouse).addressOf(salt);
        require(deployed.code.length == 0, "Salt already used");

        // Plant creation code via greenhouse.
        vm.startBroadcast();
        IGreenhouse(greenhouse).plant(salt, creationCode);
        vm.stopBroadcast();

        console.log("Deployed at", deployed);
    }

    // -- IAggor Functions --

    /// @dev Updates the aggrement distance to `agreementDistance_`.
    function setAgreementDistance(address self, uint128 agreementDistance_)
        public
    {
        vm.startBroadcast();
        IAggor(self).setAgreementDistance(agreementDistance_);
        vm.stopBroadcast();

        console.log("Updated agreement distance", agreementDistance_);
    }

    /// @dev Updates the age threshold to `ageThreshold_`.
    function setAgeThreshold(address self, uint32 ageThreshold_) public {
        vm.startBroadcast();
        IAggor(self).setAgeThreshold(ageThreshold_);
        vm.stopBroadcast();

        console.log("Updated age threshold", ageThreshold_);
    }

    // -- IAuth Functions --

    /// @dev Grants auth to address `who`.
    function rely(address self, address who) public {
        vm.startBroadcast();
        IAuth(self).rely(who);
        vm.stopBroadcast();

        console.log("Relied", who);
    }

    /// @dev Renounces auth from address `who`.
    function deny(address self, address who) public {
        vm.startBroadcast();
        IAuth(self).deny(who);
        vm.stopBroadcast();

        console.log("Denied", who);
    }
}
