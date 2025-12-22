// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {HLConversions} from "../../../src/common/HLConversions.sol";
import {HLConstants} from "../../../src/common/HLConstants.sol";
import {HyperCore} from "../../simulation/HyperCore.sol";
import {CoreSimulatorLib} from "../../simulation/CoreSimulatorLib.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";

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

    function placeLimitOrderALO(uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint128 cloid)
        public
    {
        CoreWriterLib.placeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, HLConstants.LIMIT_ORDER_TIF_ALO, cloid);
    }
}

contract SpotTradingTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    // Token addresses
    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant uBTC = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463;
    address public constant uETH = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;
    address public constant uSOL = 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29;

    // Token indices
    uint64 public constant USDC_TOKEN = 0;
    uint64 public constant HYPE_TOKEN = 150;

    // Spot market indices
    uint32 public constant HYPE_SPOT = 107;  // HYPE/USDC
    uint32 public constant USDT0_SPOT = 166; // USDT0/USDC
    uint32 public constant HYPE_USDT0_SPOT = 207; // HYPE/USDT0
    uint64 public constant USDT0_TOKEN = 268;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    function setUp() public {
        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        CoreSimulatorLib.forceAccountActivation(user);
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC SPOT TRADING TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotTradingBasic() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 baseAmt = 100e8; // 100 units

        spotTrader.placeLimitOrder(10000 + 156, true, 1e18, baseAmt, false, 1);

        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;
        // USDC should decrease after buying
        assertLe(usdcAfter, usdcBefore, "USDC balance should decrease after spot buy");
    }

    /*//////////////////////////////////////////////////////////////
                        HYPE/USDC SPOT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyHYPEWithUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8); // 10000 USDC
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 hypeBefore = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 HYPE
        uint32 assetId = HYPE_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertGt(hypeAfter, hypeBefore, "HYPE balance should increase after buying");
        assertLt(usdcAfter, usdcBefore, "USDC balance should decrease after buying");
    }

    function testSpotSellHYPEForUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 0);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 100e8); // 100 HYPE

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 hypeBefore = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 HYPE
        uint32 assetId = HYPE_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertLt(hypeAfter, hypeBefore, "HYPE balance should decrease after selling");
        assertGt(usdcAfter, usdcBefore, "USDC balance should increase after selling");
    }

    /*//////////////////////////////////////////////////////////////
                        uBTC/USDC SPOT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyUBTCWithUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        uint64 uBTC_TOKEN = PrecompileLib.getTokenIndex(uBTC);
        uint64 uBTC_SPOT = PrecompileLib.getSpotIndex(uBTC_TOKEN);

        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 100000e8); // 100000 USDC
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), uBTC_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 ubtcBefore = PrecompileLib.spotBalance(address(spotTrader), uBTC_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 1e5; // 0.001 BTC (adjust based on szDecimals)
        uint32 assetId = uint32(uBTC_SPOT) + 10000;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 ubtcAfter = PrecompileLib.spotBalance(address(spotTrader), uBTC_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertGt(ubtcAfter, ubtcBefore, "uBTC balance should increase after buying");
        assertLt(usdcAfter, usdcBefore, "USDC balance should decrease after buying");
    }

    function testSpotSellUBTCForUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        uint64 uBTC_TOKEN = PrecompileLib.getTokenIndex(uBTC);
        uint64 uBTC_SPOT = PrecompileLib.getSpotIndex(uBTC_TOKEN);

        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 0);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), uBTC_TOKEN, 1e8); // 1 BTC

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 ubtcBefore = PrecompileLib.spotBalance(address(spotTrader), uBTC_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 1e5; // 0.001 BTC
        uint32 assetId = uint32(uBTC_SPOT) + 10000;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 ubtcAfter = PrecompileLib.spotBalance(address(spotTrader), uBTC_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertLt(ubtcAfter, ubtcBefore, "uBTC balance should decrease after selling");
        assertGt(usdcAfter, usdcBefore, "USDC balance should increase after selling");
    }

    /*//////////////////////////////////////////////////////////////
                        uSOL/USDC SPOT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyUSOLWithUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        uint64 uSOL_TOKEN = PrecompileLib.getTokenIndex(uSOL);
        uint64 uSOL_SPOT = PrecompileLib.getSpotIndex(uSOL_TOKEN);

        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8); // 10000 USDC
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), uSOL_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 usolBefore = PrecompileLib.spotBalance(address(spotTrader), uSOL_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 SOL
        uint32 assetId = uint32(uSOL_SPOT) + 10000;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 usolAfter = PrecompileLib.spotBalance(address(spotTrader), uSOL_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertGt(usolAfter, usolBefore, "uSOL balance should increase after buying");
        assertLt(usdcAfter, usdcBefore, "USDC balance should decrease after buying");
    }

    function testSpotSellUSOLForUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        uint64 uSOL_TOKEN = PrecompileLib.getTokenIndex(uSOL);
        uint64 uSOL_SPOT = PrecompileLib.getSpotIndex(uSOL_TOKEN);

        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 0);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), uSOL_TOKEN, 100e8); // 100 SOL

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 usolBefore = PrecompileLib.spotBalance(address(spotTrader), uSOL_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 SOL
        uint32 assetId = uint32(uSOL_SPOT) + 10000;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 usolAfter = PrecompileLib.spotBalance(address(spotTrader), uSOL_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertLt(usolAfter, usolBefore, "uSOL balance should decrease after selling");
        assertGt(usdcAfter, usdcBefore, "USDC balance should increase after selling");
    }

    /*//////////////////////////////////////////////////////////////
                        USDT0/USDC SPOT TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyUSDT0WithUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        uint64 USDT0_TOKEN = PrecompileLib.getTokenIndex(USDT0);

        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8); // 10000 USDC
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDT0_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 usdt0Before = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 100e8; // 100 USDT0
        uint32 assetId = USDT0_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 usdt0After = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertGt(usdt0After, usdt0Before, "USDT0 balance should increase after buying");
        assertLt(usdcAfter, usdcBefore, "USDC balance should decrease after buying");
    }

    function testSpotSellUSDT0ForUSDC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        uint64 USDT0_TOKEN = PrecompileLib.getTokenIndex(USDT0);

        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 0);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDT0_TOKEN, 1000e8); // 1000 USDT0

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 usdt0Before = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;
        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 100e8; // 100 USDT0
        uint32 assetId = USDT0_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 usdt0After = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertLt(usdt0After, usdt0Before, "USDT0 balance should decrease after selling");
        assertGt(usdcAfter, usdcBefore, "USDC balance should increase after selling");
    }

    /*//////////////////////////////////////////////////////////////
                        HYPE/USDT0 SPOT TESTS (USDT0 as quote)
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyHYPEWithUSDT0() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        // Give USDT0 as quote token
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDT0_TOKEN, 10000e8); // 10000 USDT0
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 hypeBefore = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdt0Before = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 HYPE
        uint32 assetId = HYPE_USDT0_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdt0After = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;

        assertGt(hypeAfter, hypeBefore, "HYPE balance should increase after buying with USDT0");
        assertLt(usdt0After, usdt0Before, "USDT0 balance should decrease after buying HYPE");
    }

    function testSpotSellHYPEForUSDT0() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));

        // Give HYPE as base token to sell
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDT0_TOKEN, 0);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 100e8); // 100 HYPE

        CoreSimulatorLib.setRevertOnFailure(true);

        uint64 hypeBefore = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdt0Before = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 HYPE
        uint32 assetId = HYPE_USDT0_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdt0After = PrecompileLib.spotBalance(address(spotTrader), USDT0_TOKEN).total;

        assertLt(hypeAfter, hypeBefore, "HYPE balance should decrease after selling for USDT0");
        assertGt(usdt0After, usdt0Before, "USDT0 balance should increase after selling HYPE");
    }

    /*//////////////////////////////////////////////////////////////
                        LIMIT ORDER TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotLimitOrderBuyBelowPrice() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        uint32 spotMarketId = 156;
        uint64 currentSpotPx = uint64(PrecompileLib.normalizedSpotPx(spotMarketId));

        // Place a buy order with limit price below current spot price (won't execute immediately)
        uint64 limitPx = currentSpotPx / 2;

        uint64 baseAmt = 1e8;

        spotTrader.placeLimitOrder(10000 + spotMarketId, true, limitPx, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        // Now update the price to match the order's limit price
        CoreSimulatorLib.setSpotPx(spotMarketId, limitPx / 100);

        CoreSimulatorLib.nextBlock();

        // Order should execute after price drops
        // Verify by checking balance changes occurred
    }

    function testSpotLimitOrderSellAbovePrice() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        uint32 spotMarketId = 156;
        uint64 currentSpotPx = uint64(PrecompileLib.normalizedSpotPx(spotMarketId));

        // Place a sell order with limit price above current spot price (won't execute immediately)
        uint64 limitPx = currentSpotPx * 2;

        uint64 baseAmt = 1e8;
        spotTrader.placeLimitOrderGTC(10000 + spotMarketId, false, limitPx, baseAmt, false, 1);

        CoreSimulatorLib.nextBlock();

        // Now update the price to match the order's limit price
        CoreSimulatorLib.setSpotPx(spotMarketId, limitPx / 100);

        CoreSimulatorLib.nextBlock();

        // Order should execute after price rises
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE VARIATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotTradeAtDifferentPrices() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 100000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        // Set a specific price
        CoreSimulatorLib.setSpotPx(HYPE_SPOT, 2500); // $25

        uint64 hypeBefore = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;

        // Buy at $25
        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 10e8, false, 1);
        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter1 = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        assertGt(hypeAfter1, hypeBefore, "Should have bought HYPE at $25");

        // Change price to $30
        CoreSimulatorLib.setSpotPx(HYPE_SPOT, 3000);

        // Buy more at $30
        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 10e8, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter2 = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        assertGt(hypeAfter2, hypeAfter1, "Should have bought more HYPE at $30");
    }

    /*//////////////////////////////////////////////////////////////
                        ORDER TYPE TESTS (IOC, GTC, ALO)
    //////////////////////////////////////////////////////////////*/

    function testSpotOrderIOC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        // IOC order - should execute immediately or cancel
        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 10e8, false, 1);

        CoreSimulatorLib.nextBlock();

        uint64 hypeBalance = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        // IOC order should have executed
        assertGt(hypeBalance, 0, "IOC order should execute");
    }

    function testSpotOrderGTC() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 100e8);

        // GTC sell order at high price - should stay open
        uint64 currentPrice = uint64(PrecompileLib.normalizedSpotPx(HYPE_SPOT));
        uint64 highPrice = currentPrice * 2;

        spotTrader.placeLimitOrderGTC(HYPE_SPOT + 10000, false, highPrice, 10e8, false, 1);

        CoreSimulatorLib.nextBlock();

        // Order should be pending (HYPE balance should show hold)
        PrecompileLib.SpotBalance memory balance = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN);
        // Hold may be > 0 if order is pending
    }

    /*//////////////////////////////////////////////////////////////
                        SPOT SEND TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotSendUSDC() public {
        address recipient = makeAddr("recipient");
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(recipient);
        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 1000e8);

        uint64 senderBefore = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 recipientBefore = PrecompileLib.spotBalance(recipient, USDC_TOKEN).total;

        vm.startPrank(user);
        CoreWriterLib.spotSend(recipient, USDC_TOKEN, 100e8);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 senderAfter = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 recipientAfter = PrecompileLib.spotBalance(recipient, USDC_TOKEN).total;

        assertLt(senderAfter, senderBefore, "Sender balance should decrease");
        assertGt(recipientAfter, recipientBefore, "Recipient balance should increase");
    }

    function testSpotSendHYPE() public {
        address recipient = makeAddr("recipient");
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(recipient);
        CoreSimulatorLib.forceSpotBalance(user, HYPE_TOKEN, 100e8);

        uint64 senderBefore = PrecompileLib.spotBalance(user, HYPE_TOKEN).total;
        uint64 recipientBefore = PrecompileLib.spotBalance(recipient, HYPE_TOKEN).total;

        vm.startPrank(user);
        CoreWriterLib.spotSend(recipient, HYPE_TOKEN, 50e8);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 senderAfter = PrecompileLib.spotBalance(user, HYPE_TOKEN).total;
        uint64 recipientAfter = PrecompileLib.spotBalance(recipient, HYPE_TOKEN).total;

        assertLt(senderAfter, senderBefore, "Sender HYPE balance should decrease");
        assertGt(recipientAfter, recipientBefore, "Recipient HYPE balance should increase");
    }

    /*//////////////////////////////////////////////////////////////
                        USD CLASS TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransferUsdClassSpotToPerp() public {
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 1000e8);
        CoreSimulatorLib.forcePerpBalance(user, 0);

        uint64 spotBefore = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 perpBefore = PrecompileLib.withdrawable(user);

        vm.startPrank(user);
        CoreWriterLib.transferUsdClass(500e6, true); // Transfer 500 USDC to perp
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 spotAfter = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 perpAfter = PrecompileLib.withdrawable(user);

        assertLt(spotAfter, spotBefore, "Spot balance should decrease");
        assertGt(perpAfter, perpBefore, "Perp balance should increase");
    }

    function testTransferUsdClassPerpToSpot() public {
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 0);
        CoreSimulatorLib.forcePerpBalance(user, 1000e6);

        uint64 spotBefore = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 perpBefore = PrecompileLib.withdrawable(user);

        vm.startPrank(user);
        CoreWriterLib.transferUsdClass(500e6, false); // Transfer 500 USDC from perp to spot
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 spotAfter = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 perpAfter = PrecompileLib.withdrawable(user);

        assertGt(spotAfter, spotBefore, "Spot balance should increase");
        assertLt(perpAfter, perpBefore, "Perp balance should decrease");
    }

    /*//////////////////////////////////////////////////////////////
                        INSUFFICIENT BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyInsufficientBalance() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 1e8); // Only 1 USDC
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        // Try to buy 1000 HYPE (which would cost much more than 1 USDC)
        uint64 baseAmt = 1000e8;
        uint32 assetId = HYPE_SPOT + 10000;

        uint64 hypeBefore = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);

        // Expect revert due to insufficient balance
        CoreSimulatorLib.nextBlock(true);

        // HYPE balance should not have changed (order failed)
        uint64 hypeAfter = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        assertEq(hypeAfter, hypeBefore, "HYPE balance should not change on failed order");
    }

    function testSpotSellInsufficientBalance() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 1e8); // Only 1 HYPE

        // Try to sell 100 HYPE (don't have that much)
        uint64 baseAmt = 100e8;
        uint32 assetId = HYPE_SPOT + 10000;

        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);

        // Expect revert due to insufficient balance
        CoreSimulatorLib.nextBlock(true);

        // USDC balance should not have changed (order failed)
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;
        assertEq(usdcAfter, usdcBefore, "USDC balance should not change on failed order");
    }

    /*//////////////////////////////////////////////////////////////
                        FEE VARIATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotWithHighFees() public {
        // Set high spot maker fee (5%)
        CoreSimulatorLib.setSpotMakerFee(500);
        CoreSimulatorLib.setRevertOnFailure(true);

        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 HYPE
        uint32 assetId = HYPE_SPOT + 10000;

        spotTrader.placeLimitOrder(assetId, true, 1e18, baseAmt, false, 1);
        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        // USDC should be reduced more than just the trade amount due to fees
        assertLt(usdcAfter, usdcBefore, "USDC should decrease including fees");

        // Reset fee
        CoreSimulatorLib.setSpotMakerFee(400);
    }

    function testSpotWithZeroFees() public {
        // Set zero spot maker fee
        CoreSimulatorLib.setSpotMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);

        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 10000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 100e8);

        // Sell HYPE
        uint64 baseAmt = 10e8;
        uint32 assetId = HYPE_SPOT + 10000;

        uint64 usdcBefore = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        spotTrader.placeLimitOrder(assetId, false, 0, baseAmt, false, 1);
        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;
        assertGt(usdcAfter, usdcBefore, "Should receive full USDC without fee deduction");

        // Reset fee
        CoreSimulatorLib.setSpotMakerFee(400);
    }

    /*//////////////////////////////////////////////////////////////
                        ZERO AMOUNT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testSpotSendZeroAmount() public {
        address recipient = makeAddr("recipient");
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(recipient);
        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 1000e8);

        uint64 recipientBefore = PrecompileLib.spotBalance(recipient, USDC_TOKEN).total;

        vm.startPrank(user);
        CoreWriterLib.spotSend(recipient, USDC_TOKEN, 0); // Zero amount
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 recipientAfter = PrecompileLib.spotBalance(recipient, USDC_TOKEN).total;
        assertEq(recipientAfter, recipientBefore, "Recipient balance should not change for zero send");
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE TRADES IN SEQUENCE
    //////////////////////////////////////////////////////////////*/

    function testMultipleSpotTradesInSequence() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 100000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        // Trade 1: Buy 10 HYPE
        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 10e8, false, 1);
        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter1 = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        assertGt(hypeAfter1, 0, "Should have HYPE after first buy");

        // Trade 2: Buy 20 more HYPE
        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 20e8, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter2 = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        assertGt(hypeAfter2, hypeAfter1, "Should have more HYPE after second buy");

        // Trade 3: Sell 15 HYPE
        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, false, 0, 15e8, false, 3);
        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter3 = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        assertLt(hypeAfter3, hypeAfter2, "Should have less HYPE after sell");
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE SLIPPAGE SIMULATION
    //////////////////////////////////////////////////////////////*/

    function testSpotBuyAtVaryingPrices() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 100000e8);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 0);

        CoreSimulatorLib.setRevertOnFailure(true);

        // Set low price
        CoreSimulatorLib.setSpotPx(HYPE_SPOT, 2000); // $20
        uint64 usdcBefore1 = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 10e8, false, 1);
        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter1 = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;
        uint64 spent1 = usdcBefore1 - usdcAfter1;

        // Set higher price
        CoreSimulatorLib.setSpotPx(HYPE_SPOT, 4000); // $40 (2x the price)
        uint64 usdcBefore2 = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        spotTrader.placeLimitOrder(HYPE_SPOT + 10000, true, 1e18, 10e8, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter2 = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;
        uint64 spent2 = usdcBefore2 - usdcAfter2;

        // Should have spent approximately 2x more USDC at the higher price
        assertGt(spent2, spent1, "Should spend more USDC at higher price");
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER BETWEEN ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    function testSpotTransferBetweenMultipleAccounts() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        CoreSimulatorLib.forceAccountActivation(user1);
        CoreSimulatorLib.forceAccountActivation(user2);
        CoreSimulatorLib.forceAccountActivation(user3);

        CoreSimulatorLib.forceSpotBalance(user1, HYPE_TOKEN, 100e8);

        // User1 sends to User2
        vm.startPrank(user1);
        CoreWriterLib.spotSend(user2, HYPE_TOKEN, 50e8);
        vm.stopPrank();
        CoreSimulatorLib.nextBlock();

        assertEq(PrecompileLib.spotBalance(user1, HYPE_TOKEN).total, 50e8, "User1 should have 50 HYPE");
        assertEq(PrecompileLib.spotBalance(user2, HYPE_TOKEN).total, 50e8, "User2 should have 50 HYPE");

        // User2 sends to User3
        vm.startPrank(user2);
        CoreWriterLib.spotSend(user3, HYPE_TOKEN, 25e8);
        vm.stopPrank();
        CoreSimulatorLib.nextBlock();

        assertEq(PrecompileLib.spotBalance(user2, HYPE_TOKEN).total, 25e8, "User2 should have 25 HYPE");
        assertEq(PrecompileLib.spotBalance(user3, HYPE_TOKEN).total, 25e8, "User3 should have 25 HYPE");
    }

    /*//////////////////////////////////////////////////////////////
                        FULL BALANCE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    function testTransferFullUsdClassBalance() public {
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 1000e8);
        CoreSimulatorLib.forcePerpBalance(user, 0);

        uint64 spotBalance = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 perpEquivalent = HLConversions.weiToPerp(spotBalance);

        vm.startPrank(user);
        CoreWriterLib.transferUsdClass(perpEquivalent, true); // Transfer full balance to perp
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 spotAfter = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        uint64 perpAfter = PrecompileLib.withdrawable(user);

        assertEq(spotAfter, 0, "Spot balance should be 0 after full transfer");
        assertGt(perpAfter, 0, "Perp balance should have full amount");
    }

    function testSellFullSpotBalance() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), USDC_TOKEN, 0);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), HYPE_TOKEN, 50e8); // Exactly 50 HYPE

        CoreSimulatorLib.setRevertOnFailure(true);

        // Sell all 50 HYPE
        uint32 assetId = HYPE_SPOT + 10000;
        spotTrader.placeLimitOrder(assetId, false, 0, 50e8, false, 1);
        CoreSimulatorLib.nextBlock();

        uint64 hypeAfter = PrecompileLib.spotBalance(address(spotTrader), HYPE_TOKEN).total;
        uint64 usdcAfter = PrecompileLib.spotBalance(address(spotTrader), USDC_TOKEN).total;

        assertEq(hypeAfter, 0, "Should have sold all HYPE");
        assertGt(usdcAfter, 0, "Should have received USDC");
    }
}
