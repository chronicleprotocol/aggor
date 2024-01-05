// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";

import {IGreenhouse} from "greenhouse/IGreenhouse.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IUniswapV3Pool} from
    "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from
    "uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import {IAggor} from "src/IAggor.sol";
import {Aggor_BASE_QUOTE_COUNTER as Aggor} from "src/Aggor.sol";
// @todo      ^^^^ ^^^^^ ^^^^^^^ Adjust name of Aggor instance

/**
 * @notice Aggor Management Script
 */
contract AggorScript is Script {
    /// @dev Deploys a new Aggor instance via Greenhouse instance
    ///      `greenhouse` and salt `salt` with `initialAuthed` being the
    ///      address initially auth'ed.
    function deploy(
        address greenhouse,
        bytes32 salt,
        address initialAuthed,
        bool isPeggedAsset,
        uint128 peggedPrice,
        address chronicle,
        address chainlink,
        address uniswapPool,
        address uniswapBaseToken,
        address uniswapQuoteToken,
        uint8 uniswapBaseTokenDecimals,
        uint32 uniswapLookback,
        uint16 agreementDistance,
        uint32 ageThreshold
    ) public {
        // Check pegged asset mode arguments.
        require(
            (isPeggedAsset && peggedPrice != 0)
                || (!isPeggedAsset && peggedPrice == 0)
        );

        // Check Uniswap pool arguments.
        if (uniswapPool != address(0)) {
            require(uniswapBaseToken != uniswapQuoteToken);
            address token0 = IUniswapV3Pool(uniswapPool).token0();
            address token1 = IUniswapV3Pool(uniswapPool).token1();
            require(uniswapBaseToken == token0 || uniswapBaseToken == token1);
            require(uniswapQuoteToken == token0 || uniswapQuoteToken == token1);
            require(uniswapBaseTokenDecimals == IERC20(uniswapBaseToken).decimals());
            require(uniswapLookback != uint32(0));

            // Verify Uniswap TWAP is initialized.
            // Specifically it is verified that the TWAP's oldest observation is 
            // older then the uniswapLookback argument.
            uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(uniswapPool);
            require(oldestObservation + uniswapLookback < block.timestamp);
        } else {
            require(uniswapPool == address(0));
            require(uniswapBaseToken == address(0));
            require(uniswapQuoteToken == address(0));
            require(uniswapBaseTokenDecimals == uint8(0));
            require(uniswapLookback == uint32(0));
        }

        // Create creation code with constructor arguments.
        bytes memory creationCode = abi.encodePacked(
            type(Aggor).creationCode,
            abi.encode(
                initialAuthed,
                isPeggedAsset,
                peggedPrice,
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

    /// @dev Updates the aggrement distance to `agreementDistance`.
    function setAgreementDistance(address self, uint16 agreementDistance)
        public
    {
        vm.startBroadcast();
        IAggor(self).setAgreementDistance(agreementDistance);
        vm.stopBroadcast();

        console.log("Updated agreement distance", agreementDistance);
    }

    /// @dev Updates the age threshold to `ageThreshold`.
    function setAgeThreshold(address self, uint32 ageThreshold) public {
        vm.startBroadcast();
        IAggor(self).setAgeThreshold(ageThreshold);
        vm.stopBroadcast();

        console.log("Updated age threshold", ageThreshold);
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
