// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IAuth} from "chronicle-std/auth/IAuth.sol";
import {IToll} from "chronicle-std/toll/IToll.sol";
import {IChronicle} from "chronicle-std/IChronicle.sol";

import {Aggor} from "src/Aggor.sol";
import {IAggor} from "src/IAggor.sol";

/**
 * @dev Aggor Integration Test for
 *      - chain       : Ethereum
 *      - wat         : ETH/USD
 *      - oracles     : Chronicle, Chainlink
 *      - tie breaker : Uniswap Twap USDC/WETH
 */
contract AggorIntegrationTest_eth_ETH_USD is Test {
    Aggor aggor;

    // Oracle Providers:
    // Note that the Chronicle oracle is not being poked anymore. However, as
    // the oracle's value is set directly via storage overwrites this is not an
    // issue.
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
    uint128 agreementDistance = 5e16; // 5%
    uint32 ageThreshold = 1 days; // 1 day

    function setUp() public {
        // Start mainnet fork.
        vm.createSelectFork("eth");

        // Deploy aggor.
        aggor = new Aggor(
            address(this),
            address(this),
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

    // -- Tests --

    function test_ChronicleOk_ChainlinkOk_InAgreementDistance() public {
        // ETH/USD: 1,000
        uint128 chrVal = 1000e18;
        uint128 chlVal = 1000e8;

        uint32 chrAge = uint32(block.timestamp);
        uint32 chlAge = uint32(block.timestamp);

        // Set oracles.
        _setChronicle(chrVal, chrAge);
        _setChainlink(chlVal, chlAge);

        // Expected value: median(chrVal, chlVal)
        // Expected path: Both oracles valid and in agreement distance
        uint wantVal = 1000e8;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 2, goodOracleCtr: 2});

        // Read Aggor.
        uint gotVal;
        uint gotAge;
        IAggor.Status memory gotStatus;
        (gotVal, gotAge, gotStatus) = aggor.readWithStatus();

        assertEq(gotVal, wantVal);
        assertEq(gotAge, block.timestamp);
        assertEq(gotStatus.path, wantStatus.path);
        assertEq(gotStatus.goodOracleCtr, wantStatus.goodOracleCtr);
    }

    function test_ChronicleOk_ChainlinkNotOk() public {
        // ETH/USD: 1,000
        uint128 chrVal = 1000e18;
        uint128 chlVal = 1000e8;

        // Let chainlink be stale.
        uint32 chrAge = uint32(block.timestamp);
        uint32 chlAge = uint32(block.timestamp - aggor.ageThreshold() - 1);

        // Set oracles.
        _setChronicle(chrVal, chrAge);
        _setChainlink(chlVal, chlAge);

        // Expected value: chrVal in 8 decimals
        // Expected path: Only one oracle valid
        uint wantVal = 1000e8;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});

        // Read aggor.
        uint gotVal;
        uint gotAge;
        IAggor.Status memory gotStatus;
        (gotVal, gotAge, gotStatus) = aggor.readWithStatus();

        assertEq(gotVal, wantVal);
        assertEq(gotAge, block.timestamp);
        assertEq(gotStatus.path, wantStatus.path);
        assertEq(gotStatus.goodOracleCtr, wantStatus.goodOracleCtr);
    }

    function test_ChronicleNotOk_ChainlinkOk() public {
        // ETH/USD: 1,000
        uint128 chrVal = 1000e18;
        uint128 chlVal = 1000e8;

        // Let chronicle be stale.
        uint32 chrAge = uint32(block.timestamp - aggor.ageThreshold() - 1);
        uint32 chlAge = uint32(block.timestamp);

        // Set oracles.
        _setChronicle(chrVal, chrAge);
        _setChainlink(chlVal, chlAge);

        // Expected value: chl_val
        // Expected path: Only one oracle valid
        uint wantVal = 1000e8;
        IAggor.Status memory wantStatus =
            IAggor.Status({path: 4, goodOracleCtr: 1});

        // Read aggor.
        uint gotVal;
        uint gotAge;
        IAggor.Status memory gotStatus;
        (gotVal, gotAge, gotStatus) = aggor.readWithStatus();

        assertEq(gotVal, wantVal);
        assertEq(gotAge, block.timestamp);
        assertEq(gotStatus.path, wantStatus.path);
        assertEq(gotStatus.goodOracleCtr, wantStatus.goodOracleCtr);
    }

    /// @dev Verifies that its not possible to manipulate Aggor's value
    ///      derivation path in `latestAnswer()` to prevent the Chainlink
    ///      oracle from being read via capping the forwarded gas.
    ///
    /// @dev Note to execute against local forked anvil node in order to
    ///      prevent rate-limits.
    function test_latestAnswer_OOGAttack_PreventChainlink() public {
        uint128 chrVal = 2e18;
        uint128 chlVal = 1e8;

        // Set oracles.
        _setChronicle(chrVal, uint32(block.timestamp));
        _setChainlink(chlVal, uint32(block.timestamp));

        // Expect only Chronicle's value (in 8 decimals).
        uint wantVal = 2e8;

        // Call read function once to warm slots.
        aggor.latestAnswer();

        // Gas usage is an upper bound based on following solc options:
        // version        : 0.8.16
        // optimizer      : true
        // optimizer_runs : 10_000
        // via-ir         : false
        uint gasUsage = 9000;
        while (gasUsage > 500) {
            try aggor.latestAnswer{gas: gasUsage}() returns (int answer) {
                // Call returned, ie no OOG.
                // Verify whether Chainlink call was executed.
                bool chainlinkExecuted = uint(answer) != wantVal;
                if (!chainlinkExecuted) {
                    // Success! Found a gas cap to execute Chronicle call but
                    // not Chainlink, while at the same providing enough gas
                    // for Aggor to return.
                    revert("latestAnswer() vulnerable to OOG attack");
                } else {
                    // Gas cap was too much. Function executed normally.
                    gasUsage -= 1;
                }
            } catch {
                // Only possible due to OOG.
                // If this happens we provided too little gas for the call to
                // succeed.
                break;
            }
        }
    }

    /// @dev Verifies that its not possible to manipulate Aggor's value
    ///      derivation path in `latestRoundData()` to prevent the Chainlink
    ///      oracle from being read via capping the forwarded gas.
    ///
    /// @dev Note to execute against local forked anvil node in order to
    ///      prevent rate-limits.
    function test_latestRoundData_OOGAttack_PreventChainlink() public {
        uint128 chrVal = 2e18;
        uint128 chlVal = 1e8;

        // Set oracles.
        _setChronicle(chrVal, uint32(block.timestamp));
        _setChainlink(chlVal, uint32(block.timestamp));

        // Expect only Chronicle's value (in 8 decimals).
        uint wantVal = 2e8;

        // Call read function once to warm slots.
        aggor.latestRoundData();

        // Gas usage is an upper bound based on following solc options:
        // version        : 0.8.16
        // optimizer      : true
        // optimizer_runs : 10_000
        // via-ir         : false
        uint gasUsage = 10_000;
        while (gasUsage > 500) {
            try aggor.latestRoundData{gas: gasUsage}() returns (
                uint80, int answer, uint, uint, uint80
            ) {
                // Call returned, ie no OOG.
                // Verify whether Chainlink call was executed.
                bool chainlinkExecuted = uint(answer) != wantVal;
                if (!chainlinkExecuted) {
                    // Success! Found a gas cap to execute Chronicle call but
                    // not Chainlink, while at the same providing enough gas
                    // for Aggor to return.
                    revert("latestRoundData() vulnerable to OOG attack");
                } else {
                    // Gas cap was too much. Function executed normally.
                    gasUsage -= 1;
                }
            } catch {
                // Only possible due to OOG.
                // If this happens we provided too little gas for the call to
                // succeed.
                break;
            }
        }
    }

    /// @dev Verifies that its not possible to manipulate Aggor's value
    ///      derivation path in `readWithStatus()` to prevent the Chainlink
    ///      oracle from being read via capping the forwarded gas.
    ///
    /// @dev Note to execute against local forked anvil node in order to
    ///      prevent rate-limits.
    function test_readWithStatus_OOGAttack_PreventChainlink() public {
        uint128 chrVal = 2e18;
        uint128 chlVal = 1e8;

        // Set oracles.
        _setChronicle(chrVal, uint32(block.timestamp));
        _setChainlink(chlVal, uint32(block.timestamp));

        // Expect only Chronicle's value (in 8 decimals).
        uint wantVal = 2e8;

        // Call read function once to warm slots.
        aggor.readWithStatus();

        // Gas usage is an upper bound based on following solc options:
        // version        : 0.8.16
        // optimizer      : true
        // optimizer_runs : 10_000
        // via-ir         : false
        uint gasUsage = 10_000;
        while (gasUsage > 500) {
            try aggor.readWithStatus{gas: gasUsage}() returns (
                uint val, uint, IAggor.Status memory
            ) {
                // Call returned, ie no OOG.
                // Verify whether Chainlink call was executed.
                bool chainlinkExecuted = val != wantVal;
                if (!chainlinkExecuted) {
                    // Success! Found a gas cap to execute Chronicle call but
                    // not Chainlink, while at the same providing enough gas
                    // for Aggor to return.
                    revert("readWithStatus() vulnerable to OOG attack");
                } else {
                    // Gas cap was too much. Function executed normally.
                    gasUsage -= 1;
                }
            } catch {
                // Only possible due to OOG.
                // If this happens we provided too little gas for the call to
                // succeed.
                break;
            }
        }
    }
}

interface IChainlinkAggregatorV3_Aggregator {
    function aggregator() external view returns (address);
}
