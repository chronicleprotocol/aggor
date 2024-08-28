// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";

import {IAggor} from "src/IAggor.sol";
import {ChronicleAggor_BASE_QUOTE_COUNTER as Aggor} from "src/Aggor.sol";
// @todo               ^^^^ ^^^^^ ^^^^^^^ Adjust name of Aggor instance

/**
 * @notice Aggor Management Script
 */
contract AggorScript is Script {
    /// @dev Deploys a new Aggor instance with `initialAuthed` being the address
    ///      initially auth'ed.
    function deploy(
        address initialAuthed,
        address bud,
        address chronicle,
        address chainlink,
        address uniswapPool,
        address uniswapBaseToken,
        address uniswapQuoteToken,
        uint8 uniswapBaseTokenDecimals,
        uint8 uniswapQuoteTokenDecimals,
        uint32 uniswapLookback,
        uint128 agreementDistance,
        uint32 ageThreshold
    ) public {
        vm.startBroadcast();
        address deployed = address(
            new Aggor(
                initialAuthed,
                bud,
                chronicle,
                chainlink,
                uniswapPool,
                uniswapBaseToken,
                uniswapQuoteToken,
                uniswapBaseTokenDecimals,
                uniswapQuoteTokenDecimals,
                uniswapLookback,
                agreementDistance,
                ageThreshold
            )
        );
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
