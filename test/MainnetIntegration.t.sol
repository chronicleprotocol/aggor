// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IToll} from "chronicle-std/toll/IToll.sol";

import "uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import {LibCalc} from "src/libs/LibCalc.sol";
import {LibUniswapOracles} from "src/libs/LibUniswapOracles.sol";
import {Aggor} from "src/Aggor.sol";

import {IChainlinkAggregatorV3} from
    "src/interfaces/_external/IChainlinkAggregatorV3.sol";

// @todo Delete and swap with Scribe contract, when one is avaiable onchain.
//       https://app.shortcut.com/chronicle-labs/story/2660/aggor-integration-test-to-use-scribe-contract
interface DeleteMeIMedianizer {
    function wat() external view returns (bytes32 wat);
    function read() external view returns (uint value);
    function age() external view returns (uint32 age);
}

contract DeleteMeMedianizerWrapper {
    address medianizer;

    constructor(address medianizer_) {
        medianizer = medianizer_;
    }

    function wat() external view returns (bytes32) {
        return DeleteMeIMedianizer(medianizer).wat();
    }

    function tryReadWithAge()
        external
        view
        returns (bool isValid, uint value, uint age)
    {
        uint val = DeleteMeIMedianizer(medianizer).read();
        return (val > 0, val, uint(DeleteMeIMedianizer(medianizer).age()));
    }
}

// Integration test queries the real Uniswap WETHUSDT pool and verifies mean.
contract MainnetIntegrationTest is Test {
    /// @dev Uniswap pool
    address constant UNI_POOL_WETHUSDT =
        0x11b815efB8f581194ae79006d24E0d814B7697F6;

    /// @dev WETH ERC-20 contract
    address constant UNI_TOKEN_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    /// @dev USDT ERC-20 contract
    address constant UNI_TOKEN_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    /// @dev MedianETHUSD
    ///      https://etherscan.io/address/0x64DE91F5A373Cd4c28de3600cB34C7C6cE410C85#code
    address constant MEDIAN_ETHUSD = 0x64DE91F5A373Cd4c28de3600cB34C7C6cE410C85;
    // Authed on the above:
    address constant PAUSE_PROXY = 0xBE8E3e3618f7474F8cB1d074A26afFef007E98FB;

    address constant CHAINLINK_ETHUSD =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    /// @dev Decimals of Uni base pair
    uint8 constant BASE_DEC = 18;

    /// @dev Decimals of Uni quote pair
    uint8 constant QUOTE_DEC = 6;

    Aggor aggor;
    DeleteMeMedianizerWrapper medianWrapper;

    function setUp() public {
        // Create mainnet fork.
        vm.createSelectFork("mainnet");

        // Allow our test to read MedianETHUSD
        medianWrapper = new DeleteMeMedianizerWrapper(MEDIAN_ETHUSD);
        vm.prank(PAUSE_PROXY);
        IToll(address(MEDIAN_ETHUSD)).kiss(address(medianWrapper));

        aggor = new Aggor(
            address(this),
            address(medianWrapper),
            CHAINLINK_ETHUSD,
            UNI_POOL_WETHUSDT,
            true
        );
        IToll(address(aggor)).kiss(address(this));
    }

    // Full integration test, price values will not be deterministic
    function testIntegration_Mainnet() public {
        (, uint chronval,) = medianWrapper.tryReadWithAge();
        assertTrue(chronval > 0);

        uint unival = LibUniswapOracles.readOracle(
            UNI_POOL_WETHUSDT, UNI_TOKEN_WETH, UNI_TOKEN_USDT, BASE_DEC, 300
        );
        assertTrue(unival > 0);

        console2.log("Uni source   ", unival);
        unival = LibCalc.scale(unival, QUOTE_DEC, BASE_DEC);
        console2.log("Uni scaled   ", unival);

        (, int chainvalSource,,,) =
            IChainlinkAggregatorV3(CHAINLINK_ETHUSD).latestRoundData();
        assertTrue(chainvalSource > 0);
        console2.log("Chain source ", chainvalSource);
        uint chainval = LibCalc.scale(
            uint(chainvalSource),
            uint(IChainlinkAggregatorV3(CHAINLINK_ETHUSD).decimals()),
            BASE_DEC
        );
        console2.log("Chain scaled ", chainval);
        console2.log("Chron source ", chronval);

        uint spread =
            LibCalc.pctDiff(uint128(chronval), uint128(chainval), 10_000);
        uint spreadUni =
            LibCalc.pctDiff(uint128(chronval), uint128(unival), 10_000);
        console2.log("Spread       ", spread);
        console2.log("Spread/uni   ", spreadUni);

        // Test mean with Chainlink
        aggor.setSpread(uint16(spread) + 1);
        aggor.poke();
        console2.log("Aggor(chain) ", aggor.read());
        uint mean = (chronval + chainval) / 2;
        assertEq(aggor.read(), mean);

        // Test closest to previous value with Chainlink
        aggor.setSpread(0);
        aggor.poke();
        console2.log("Aggor(chain) ", aggor.read());
        assertEq(
            aggor.read(),
            LibCalc.distance(mean, chronval) < LibCalc.distance(mean, chainval)
                ? chronval
                : chainval
        );

        // Switch to Uniswap
        aggor.useUniswap(true);

        // Test mean with Uni
        aggor.setSpread(uint16(spreadUni) + 1);
        aggor.poke();
        console2.log("Aggor(uni)   ", aggor.read());
        mean = (chronval + unival) / 2;
        assertEq(aggor.read(), mean);

        // Test closest to previous value with Uni
        aggor.setSpread(0);
        aggor.poke();
        console2.log("Aggor(uni)   ", aggor.read());
        assertEq(
            aggor.read(),
            LibCalc.distance(mean, chronval) < LibCalc.distance(mean, unival)
                ? chronval
                : unival
        );

        // Switch back to Chainlink and verify state has changed.
        aggor.useUniswap(false);
        assertTrue(!aggor.uniswapSelected());
    }

    // Ensure that Aggor will revert if dev is requesting a lookback period
    // that is too far.
    function testIntegration_UniswapLookback() public {
        aggor.useUniswap(true);
        assertTrue(aggor.uniswapSelected());

        aggor.poke();

        vm.expectRevert();
        aggor.setUniSecondsAgo(type(uint32).max);

        aggor.poke();
    }
}
