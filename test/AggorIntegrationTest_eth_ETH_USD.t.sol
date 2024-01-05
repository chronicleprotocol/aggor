// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";
import {IChronicle} from "chronicle-std/IChronicle.sol";

import {Aggor} from "src/Aggor.sol";

/**
 * @dev Aggor Integration Test for
 *      - chain       : Ethereum
 *      - wat         : ETH/USD
 *      - oracles     : Chronicle, Chainlink
 *      - tie breaker : Uniswap Twap USDC/WETH
 */
contract AggorIntegrationTest_eth_ETH_USD is Test {
    Aggor aggor;

    // Pegged asset mode:
    bool isPeggedAsset = false;
    uint128 peggedPrice = 0;

    // Oracle Providers:
    address chronicle = address(0x1174948681bb05748E3682398d9b7a6836B07554);
    address chainlink = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    // Twap Provider: Uniswap USDC/WETH pool
    address uniswapPool = address(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    // Base token: USDC
    address uniswapBaseToken =
        address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    // Quote token: WETH
    address uniswapQuoteToken =
        address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // Base token decimals: USDC.decimals()
    uint8 uniswapBaseDec = 6;
    // Twap lookback in seconds: 1 hour
    uint32 uniswapLookback = 1 hours;

    // Configurations:
    uint16 agreementDistance = 500; // 5%
    uint32 ageThreshold = 1 days; // 1 day

    function setUp() public {
        // Start mainnet fork.
        vm.createSelectFork("http://127.0.0.1:8545");

        // Deploy aggor.
        aggor = new Aggor(
            address(this),
            isPeggedAsset,
            peggedPrice,
            chronicle,
            chainlink,
            uniswapPool,
            uniswapBaseToken,
            uniswapQuoteToken,
            uniswapBaseDec,
            uniswapLookback,
            agreementDistance,
            ageThreshold
        );

        // Kiss aggor on chronicle oracle.
        vm.prank(IAuth(chronicle).authed()[0]);
        IToll(chronicle).kiss(address(aggor));

        // Kiss address(this) on aggor.
        IToll(address(aggor)).kiss(address(this));
    }

    function _setChronicle(uint128 val, uint32 age) internal {
        // Note that Chronicle's Ethereum mainnet oracles (ScribeOptimistic) have
        // two PokeData slots. However, we can always use the _pokeData as long
        // as the age being set is newer than _opPokeData's.
        //
        // The PokeData struct is defined as:
        // struct PokeData { uint128 val; uint32 age; }
        bytes32 pokeData = bytes32(uint(age) << 128 | uint(val));

        // Storage slot for _pokeData: 4
        vm.store({target: chronicle, slot: bytes32(uint(4)), value: pokeData});

        // Storage slot for _opPokeData: 8
        // Note to empty storage slot.
        vm.store({target: chronicle, slot: bytes32(uint(8)), value: bytes32("")});
    }

    function _setChainlink(uint128 val, uint32 age) internal {
        // Get aggregator for current phrase.
        address aggregator =
            IChainlinkAggregatorV3_Aggregator(chainlink).aggregator();

        // Aggregator storage:
        //
        // Data returned by latestRoundData() is stored in following places:
        // - roundId         : s_hotVars.latestAggregatorRoundId
        // - answer          : s_transmissions[roundId].answer
        // - startedAt       : s_transmissions[roundId].timestamp
        // - updatedAt       : s_transmissions[roundId].timestamp
        // - answeredInRound : s_hotVars.latestAggregatorRoundId
        //
        // s_hotVars (slot 43):
        // struct HotVars {
        //  bytes16 latestConfigDigest;
        //  uint40 latestEpochAndRound;
        //  uint8 threshold;
        //  uint32 latestAggregatorRoundId;
        // }
        //
        // s_transmissions (slot 44):
        // struct Transmission { int192 answer; uint64 timestamp; }

        // Set s_hotVars.latestAggregatorRoundId
        uint32 roundId = uint32(8807);
        bytes32 s_hotVars = bytes32(uint(roundId) << 176);
        vm.store({target: aggregator, slot: bytes32(uint(43)), value: s_hotVars});

        // Set s_transmissions[roundId]'s answer and timestamp.
        bytes32 s_transmissions_roundId_slot =
            keccak256(abi.encodePacked(uint(roundId), uint(44)));
        bytes32 s_transmissions_roundId = bytes32(uint(age) << 192 | uint(val));
        vm.store({
            target: aggregator,
            slot: s_transmissions_roundId_slot,
            value: s_transmissions_roundId
        });
    }

    function _setTWAP(uint128 val, uint age) internal {}

    // -- Tests --

    function test_ChronicleOk_ChainlinkOk_InAgreementDistance() public {
        // ETH/USD: 1,000
        uint128 chr_val = 1000e18;
        uint128 chl_val = 1000e8;

        uint32 chr_age = uint32(block.timestamp);
        uint32 chl_age = uint32(block.timestamp);

        // Set oracles.
        _setChronicle(chr_val, chr_age);
        _setChainlink(chl_val, chl_age);

        // Expected aggor value: median(chr_val, chl_val)
        uint want = 1000e8;

        // Read Aggor.
        uint got = uint(aggor.latestAnswer());

        assertEq(got, want);
    }

    function test_ChronicleOk_ChainlinkOk_NotInAgreementDistance() public {
        uint128 chr_val = 1000e18;
        uint128 chl_val = 1100e8; // 10% difference

        uint32 chr_age = uint32(block.timestamp);
        uint32 chl_age = uint32(block.timestamp);

        // Set oracles.
        _setChronicle(chr_val, chr_age);
        _setChainlink(chl_val, chl_age);

        // Set twap.
        // TODO:
    }

    function test_ChronicleOk_ChainlinkNotOk() public {
        // ETH/USD: 1,000
        uint128 chr_val = 1000e18;
        uint128 chl_val = 1000e8;

        // Let chainlink be stale.
        uint32 chr_age = uint32(block.timestamp);
        uint32 chl_age = uint32(block.timestamp - aggor.ageThreshold() - 1);

        // Set oracles.
        _setChronicle(chr_val, chr_age);
        _setChainlink(chl_val, chl_age);

        // Expected value: chr_val in 8 decimals
        uint want = 1000e8;

        // Read aggor.
        uint got = uint(aggor.latestAnswer());

        assertEq(got, want);
    }

    function test_ChronicleNotOk_ChainlinkOk() public {
        // ETH/USD: 1,000
        uint128 chr_val = 1000e18;
        uint128 chl_val = 1000e8;

        // Let chronicle be stale.
        uint32 chr_age = uint32(block.timestamp - aggor.ageThreshold() - 1);
        uint32 chl_age = uint32(block.timestamp);

        // Set oracles.
        _setChronicle(chr_val, chr_age);
        _setChainlink(chl_val, chl_age);

        // Expected value: chl_val
        uint want = 1000e8;

        // Read aggor.
        uint got = uint(aggor.latestAnswer());

        assertEq(got, want);
    }

    function test_ChronicleNotOk_ChainlinkNotOk() public {}
}

interface IChainlinkAggregatorV3_Aggregator {
    function aggregator() external view returns (address);
}
