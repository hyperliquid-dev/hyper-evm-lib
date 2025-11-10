// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {HLConversions} from "../../src/common/HLConversions.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";
import {BridgingExample} from "../../src/examples/BridgingExample.sol";
import {HyperCore} from "../simulation/HyperCore.sol";
import {L1Read} from "../utils/L1Read.sol";
import {HypeTradingContract} from "../utils/HypeTradingContract.sol";
import {CoreSimulatorLib} from "../simulation/CoreSimulatorLib.sol";
import {RealL1Read} from "../utils/RealL1Read.sol";
import {CoreWriterLib} from "../../src/CoreWriterLib.sol";
import {VaultExample} from "../../src/examples/VaultExample.sol";
import {StakingExample} from "../../src/examples/StakingExample.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract OfflineTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    BridgingExample public bridgingExample;

    L1Read l1Read;

    function setUp() public {

        // set up the HyperCore simulation
        hyperCore = CoreSimulatorLib.init();

        hyperCore.setUseRealL1Read(false);

        bridgingExample = new BridgingExample();

        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(address(bridgingExample));

        assertEq(PrecompileLib.coreUserExists(user), true);
        assertEq(PrecompileLib.coreUserExists(address(bridgingExample)), true);


        l1Read = new L1Read();
    }

    function test_offline_bridgeHypeToCore() public {
        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreById{value: 1e18}(150, 1e18);

        (uint64 total, uint64 hold, uint64 entryNtl) =
            abi.decode(abi.encode(PrecompileLib.spotBalance(address(bridgingExample), 150)), (uint64, uint64, uint64));
        assertEq(total, 0);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) =
            abi.decode(abi.encode(PrecompileLib.spotBalance(address(bridgingExample), 150)), (uint64, uint64, uint64));
        assertEq(total, 1e8);
    }


    function test_offline_bridgeToCoreAndSend() public {
        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreAndSendHype{value: 1e18}(1e18, address(user));

        (uint64 total, uint64 hold, uint64 entryNtl) =
            abi.decode(abi.encode(PrecompileLib.spotBalance(address(user), 150)), (uint64, uint64, uint64));
        assertEq(total, 0);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) =
            abi.decode(abi.encode(PrecompileLib.spotBalance(address(user), 150)), (uint64, uint64, uint64));
        assertEq(total, 1e8);
    }

    function test_offline_spotPrice() public {
        uint64 px = PrecompileLib.spotPx(107);
        assertEq(px, 0);

        CoreSimulatorLib.setSpotPx(107, 40e6);

        px = hyperCore.readSpotPx(107);
        assertEq(px, 40e6);
    }

    function test_offline_spotTrading() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 0, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        CoreSimulatorLib.setRevertOnFailure(true);
        CoreSimulatorLib.setSpotPx(107, 40e6); // this represents a price of 40 USD per HYPE (represented with 8-szDecimals decimals)

        uint64 baseAmt = 100e8; // 100 HYPE
        uint64 quoteAmt = 10000e8; // 10k USDC (or quote token)

        // Store balances BEFORE order
        uint256 balanceAsset150Before = PrecompileLib.spotBalance(address(spotTrader), 150).total;
        uint256 balanceAsset0Before = PrecompileLib.spotBalance(address(spotTrader), 0).total;
        
        console.log("=== BEFORE ORDER ===");
        console.log("Asset 150 balance:", balanceAsset150Before);
        console.log("Asset 0 balance:", balanceAsset0Before);
        console.log("Order: BUY", baseAmt, "base at price", quoteAmt);

        spotTrader.placeLimitOrder(10000 + 107, true, quoteAmt, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        // Store balances AFTER order execution
        uint256 balanceAsset150After = PrecompileLib.spotBalance(address(spotTrader), 150).total;
        uint256 balanceAsset0After = PrecompileLib.spotBalance(address(spotTrader), 0).total;
        
        console.log("\n=== AFTER ORDER ===");
        console.log("Asset 150 balance:", balanceAsset150After);
        console.log("Asset 0 balance:", balanceAsset0After);
        
        console.log("\n=== CHANGES ===");
        console.log("Asset 150 change:", int256(balanceAsset150After) - int256(balanceAsset150Before));
        console.log("Asset 0 change:", int256(balanceAsset0After) - int256(balanceAsset0Before));
        
        // Verify the swap occurred as expected
        // For a BUY order: asset 0 (quote) should decrease, asset 150 (base) should increase
        assertLt(balanceAsset0After, balanceAsset0Before, "Quote asset should decrease");
        assertGt(balanceAsset150After, balanceAsset150Before, "Base asset should increase");
    }

    function test_offline_spot_limitOrder() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 0, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 150, 1e18);

        CoreSimulatorLib.setSpotPx(107, 40e6);

        // Log the current spot price before placing order
        uint32 spotMarketId = 107;
        uint64 currentSpotPx = uint64(PrecompileLib.normalizedSpotPx(spotMarketId));


        console.log("currentSpotPx", currentSpotPx);
        console.log("=== INITIAL STATE ===");
        console.log("Current spot price for market 107:", currentSpotPx);

        // Place a buy order with limit price below current spot price (won't execute immediately)
        uint64 limitPx = currentSpotPx / 2; // Set limit price below current price
        uint64 baseAmt = 1e8; // 1 HYPE
        
        console.log("Placing buy order:");
        console.log("  Limit price:", limitPx);
        console.log("  Base amount:", baseAmt);
        console.log("  Expected executeNow:", limitPx >= currentSpotPx ? "true" : "false");

        // Store balances BEFORE order placement
        uint256 balanceAsset150Before = PrecompileLib.spotBalance(address(spotTrader), 150).total;
        uint256 balanceAsset0Before = PrecompileLib.spotBalance(address(spotTrader), 0).total;
        
        console.log("\n=== BEFORE ORDER PLACEMENT ===");
        console.log("Asset 150 balance:", balanceAsset150Before);
        console.log("Asset 0 balance:", balanceAsset0Before);

        spotTrader.placeLimitOrder(10000 + spotMarketId, true, limitPx, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        // Store balances AFTER first block (order pending)
        uint256 balanceAsset150AfterBlock1 = PrecompileLib.spotBalance(address(spotTrader), 150).total;
        uint256 balanceAsset0AfterBlock1 = PrecompileLib.spotBalance(address(spotTrader), 0).total;
        
        console.log("\n=== AFTER FIRST BLOCK (Order Pending) ===");
        console.log("Asset 150 balance:", balanceAsset150AfterBlock1);
        console.log("Asset 0 balance:", balanceAsset0AfterBlock1);
        console.log("Asset 150 change:", int256(balanceAsset150AfterBlock1) - int256(balanceAsset150Before));
        console.log("Asset 0 change:", int256(balanceAsset0AfterBlock1) - int256(balanceAsset0Before));

        // Now update the price to match the order's limit price
        console.log("\n=== UPDATING PRICE ===");
        console.log("Setting spot price to:", limitPx/100);
        CoreSimulatorLib.setSpotPx(spotMarketId, limitPx/100);

        CoreSimulatorLib.nextBlock();

        // Store balances AFTER price update (order executed)
        uint256 balanceAsset150AfterExecution = PrecompileLib.spotBalance(address(spotTrader), 150).total;
        uint256 balanceAsset0AfterExecution = PrecompileLib.spotBalance(address(spotTrader), 0).total;
        
        console.log("\n=== AFTER PRICE UPDATE (Order Executed) ===");
        console.log("Asset 150 balance:", balanceAsset150AfterExecution);
        console.log("Asset 0 balance:", balanceAsset0AfterExecution);
        console.log("Asset 150 change from pending:", int256(balanceAsset150AfterExecution) - int256(balanceAsset150AfterBlock1));
        console.log("Asset 0 change from pending:", int256(balanceAsset0AfterExecution) - int256(balanceAsset0AfterBlock1));
        
        console.log("\n=== TOTAL CHANGES (from start) ===");
        console.log("Asset 150 total change:", int256(balanceAsset150AfterExecution) - int256(balanceAsset150Before));
        console.log("Asset 0 total change:", int256(balanceAsset0AfterExecution) - int256(balanceAsset0Before));
        
        // Verify the limit order executed after price update
        // For a BUY order: asset 0 (quote) should decrease, asset 150 (base) should increase
        assertLt(balanceAsset0AfterExecution, balanceAsset0Before, "Quote asset should decrease after execution");
        assertGt(balanceAsset150AfterExecution, balanceAsset150Before, "Base asset should increase after execution");
    }
}

contract SpotTrader {
    function placeLimitOrder(uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint128 cloid)
        public
    {
        CoreWriterLib.placeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, HLConstants.LIMIT_ORDER_TIF_IOC, cloid);
    }

    function placeLimitOrderGTC(uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint128 cloid)
        public
    {
        CoreWriterLib.placeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, HLConstants.LIMIT_ORDER_TIF_GTC, cloid);
    }

    function bridgeToCore(address asset, uint64 amount) public {
        CoreWriterLib.bridgeToCore(asset, amount);
    }
}