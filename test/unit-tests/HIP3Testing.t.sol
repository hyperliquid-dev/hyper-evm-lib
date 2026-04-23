// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {CoreWriterLib} from "../../src/CoreWriterLib.sol";
import {HLConversions} from "../../src/common/HLConversions.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";

import {HyperCore} from "../simulation/HyperCore.sol";
import {CoreSimulatorLib} from "../simulation/CoreSimulatorLib.sol";

import {HypeTradingContract} from "../utils/HypeTradingContract.sol";

/// @title HIP3Testing
/// @notice End-to-end coverage of the HIP-3 additions to the simulator.
/// @dev Exercises lazy per-(user, dex) seeding, cross-dex sendAsset validation,
///      the dex → quote-token registry, and HIP-3 perp trading. Every flow that
///      goes through CoreWriter is followed by CoreSimulatorLib.nextBlock() before
///      assertions, so the queued actions actually execute.
contract HIP3Testing is Test {
    // Token / dex constants mirroring the seed registry in CoreState
    uint64 constant USDC_TOKEN = 0;
    uint64 constant USDE_TOKEN = 235;
    uint64 constant USDT0_TOKEN = 268;
    uint64 constant USDH_TOKEN = 360;

    uint32 constant DEX_DEFAULT = 0;
    uint32 constant DEX_USDC_1 = 1;   // xyz perps
    uint32 constant DEX_USDH_2 = 2;
    uint32 constant DEX_USDH_3 = 3;
    uint32 constant DEX_USDE_4 = 4;
    uint32 constant DEX_USDH_5 = 5;
    uint32 constant DEX_USDC_6 = 6;
    uint32 constant DEX_USDT0_7 = 7;

    // NVDA perp on dex 1 (hip3 asset id = 100000 + dex*10000 + idx)
    uint32 constant NVDA_PERP_INDEX = 10002;
    uint32 constant NVDA_ASSET_ID = 110002;

    address constant USDC_EVM = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

    HyperCore hyperCore;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        hyperCore = CoreSimulatorLib.init();
    }

    /*//////////////////////////////////////////////////////////////
                          DEX QUOTE-TOKEN REGISTRY
    //////////////////////////////////////////////////////////////*/

    /// @notice The constructor must have seeded the known HIP-3 dexes.
    /// We exercise the registry indirectly: a SPOT→perp sendAsset with the
    /// matching collateral token must succeed, and one with a mismatched
    /// token must revert.
    function test_registry_knownDexes_acceptMatchingCollateral() public {
        _bridgeUsdcToCore(makeAddr("u_reg_1"), 1000e6);
        address u = makeAddr("u_reg_1");

        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), HLConstants.SPOT_DEX, DEX_USDC_1, USDC_TOKEN, 100e8);
        CoreSimulatorLib.nextBlock();

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), 100e6, "dex 1 should receive 100 USDC in perp units");
    }

    function test_registry_mismatchedCollateralReverts() public {
        _bridgeUsdcToCore(makeAddr("u_reg_2"), 1000e6);
        address u = makeAddr("u_reg_2");

        uint64 spotBefore = PrecompileLib.spotBalance(u, USDC_TOKEN).total;
        uint64 perpBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);

        vm.prank(u);
        // dex 1 expects USDC (token 0); sender requests USDH (token 360) — must be dropped
        CoreWriterLib.sendAsset(u, address(0), HLConstants.SPOT_DEX, DEX_USDC_1, USDH_TOKEN, 100e8);
        CoreSimulatorLib.nextBlock(); // default: revertOnFailure = false → swallow & roll back

        assertEq(
            PrecompileLib.spotBalance(u, USDC_TOKEN).total,
            spotBefore,
            "spot balance should be unchanged"
        );
        assertEq(
            hyperCore.readPerpBalance(u, DEX_USDC_1),
            perpBefore,
            "dex 1 balance should be unchanged"
        );
    }

    /// @notice registerDexQuoteToken allows tests to add a new HIP-3 dex.
    function test_registry_canExtendWithNewDex() public {
        uint32 customDex = 42;
        uint64 customCollateral = USDT0_TOKEN;

        hyperCore.registerDexQuoteToken(customDex, customCollateral);

        address u = makeAddr("u_reg_3");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forceSpotBalance(u, customCollateral, 1e10);

        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), HLConstants.SPOT_DEX, customDex, customCollateral, 1e10);
        CoreSimulatorLib.nextBlock();

        // 1e10 wei (8 dec) → 1e8 perp units (6 dec)
        assertEq(hyperCore.readPerpBalance(u, customDex), 1e8, "custom dex should receive credit");
    }

    function test_registry_unregisteredDexRejectedOnTransfer() public {
        address u = makeAddr("u_reg_4");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forceSpotBalance(u, USDC_TOKEN, 1e10);

        uint64 spotBefore = PrecompileLib.spotBalance(u, USDC_TOKEN).total;

        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), HLConstants.SPOT_DEX, 99, USDC_TOKEN, 1e8);
        CoreSimulatorLib.nextBlock();

        assertEq(
            PrecompileLib.spotBalance(u, USDC_TOKEN).total,
            spotBefore,
            "transfer to unregistered dex must be dropped"
        );
    }

    /*//////////////////////////////////////////////////////////////
                      SPOT → HIP-3 DEX sendAsset
    //////////////////////////////////////////////////////////////*/

    function test_sendAsset_spotToHip3Dex_usdc() public {
        address u = makeAddr("u_s2p_usdc");
        _bridgeUsdcToCore(u, 1000e6);

        uint64 spotBefore = PrecompileLib.spotBalance(u, USDC_TOKEN).total;
        uint64 perpBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 amountWei = 500e8;

        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), HLConstants.SPOT_DEX, DEX_USDC_1, USDC_TOKEN, amountWei);
        CoreSimulatorLib.nextBlock();

        uint64 spotAfter = PrecompileLib.spotBalance(u, USDC_TOKEN).total;
        uint64 perpAfter = hyperCore.readPerpBalance(u, DEX_USDC_1);

        assertEq(spotBefore - spotAfter, amountWei, "spot should decrease by amountWei");
        assertEq(perpAfter - perpBefore, amountWei / 1e2, "perp should increase by perpAmount");
    }

    function test_sendAsset_spotToHip3Dex_toOtherUser() public {
        address sender = makeAddr("u_s2p_sender");
        address recipient = makeAddr("u_s2p_recipient");
        _bridgeUsdcToCore(sender, 1000e6);

        uint64 amountWei = 250e8;
        uint64 perpRecipientBefore = hyperCore.readPerpBalance(recipient, DEX_USDC_1);

        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(sender);
        CoreWriterLib.sendAsset(recipient, address(0), HLConstants.SPOT_DEX, DEX_USDC_1, USDC_TOKEN, amountWei);
        CoreSimulatorLib.nextBlock();

        uint64 perpRecipientAfter = hyperCore.readPerpBalance(recipient, DEX_USDC_1);
        assertEq(
            perpRecipientAfter - perpRecipientBefore,
            amountWei / 1e2,
            "recipient perp balance should increase"
        );
    }

    /*//////////////////////////////////////////////////////////////
                      HIP-3 DEX → SPOT sendAsset
    //////////////////////////////////////////////////////////////*/

    function test_sendAsset_hip3DexToSpot_usdc() public {
        address u = makeAddr("u_p2s_usdc");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 500e6);

        uint64 spotBefore = PrecompileLib.spotBalance(u, USDC_TOKEN).total;
        uint64 perpBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 amountWei = 200e8;

        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), DEX_USDC_1, HLConstants.SPOT_DEX, USDC_TOKEN, amountWei);
        CoreSimulatorLib.nextBlock();

        uint64 spotAfter = PrecompileLib.spotBalance(u, USDC_TOKEN).total;
        uint64 perpAfter = hyperCore.readPerpBalance(u, DEX_USDC_1);

        assertEq(spotAfter - spotBefore, amountWei, "spot should receive amountWei");
        assertEq(perpBefore - perpAfter, amountWei / 1e2, "perp should decrease by perpAmount");
    }

    function test_sendAsset_hip3DexToSpot_wrongToken_reverts() public {
        address u = makeAddr("u_p2s_wrongtok");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 500e6);

        uint64 perpBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 spotBefore = PrecompileLib.spotBalance(u, USDH_TOKEN).total;

        vm.prank(u);
        // dex 1 uses USDC but caller claims USDH outbound → must be dropped
        CoreWriterLib.sendAsset(u, address(0), DEX_USDC_1, HLConstants.SPOT_DEX, USDH_TOKEN, 100e8);
        CoreSimulatorLib.nextBlock();

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), perpBefore, "perp unchanged");
        assertEq(
            PrecompileLib.spotBalance(u, USDH_TOKEN).total,
            spotBefore,
            "spot USDH unchanged"
        );
    }

    /*//////////////////////////////////////////////////////////////
                      HIP-3 DEX → HIP-3 DEX sendAsset
    //////////////////////////////////////////////////////////////*/

    function test_sendAsset_crossDex_sameQuoteToken_succeeds() public {
        // dex 1 (USDC) → dex 6 (USDC): allowed
        address u = makeAddr("u_p2p_same");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 1000e6);

        uint64 srcBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 dstBefore = hyperCore.readPerpBalance(u, DEX_USDC_6);
        uint64 amountWei = 300e8;

        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), DEX_USDC_1, DEX_USDC_6, USDC_TOKEN, amountWei);
        CoreSimulatorLib.nextBlock();

        uint64 srcAfter = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 dstAfter = hyperCore.readPerpBalance(u, DEX_USDC_6);

        assertEq(srcBefore - srcAfter, amountWei / 1e2, "source dex balance decreases");
        assertEq(dstAfter - dstBefore, amountWei / 1e2, "destination dex balance increases");
    }

    function test_sendAsset_crossDex_differentQuoteToken_reverts() public {
        // dex 1 (USDC) → dex 2 (USDH): disallowed
        address u = makeAddr("u_p2p_diff");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 1000e6);

        uint64 srcBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 dstBefore = hyperCore.readPerpBalance(u, DEX_USDH_2);

        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), DEX_USDC_1, DEX_USDH_2, USDC_TOKEN, 100e8);
        CoreSimulatorLib.nextBlock();

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), srcBefore, "source unchanged");
        assertEq(hyperCore.readPerpBalance(u, DEX_USDH_2), dstBefore, "dest unchanged");
    }

    /*//////////////////////////////////////////////////////////////
                       LAZY DEX INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Reading a HIP-3 margin summary for a fresh account should
    /// fall through to real chain state and return zeros (no sim inflation).
    function test_lazyInit_freshAccountReadsReturnChainState() public {
        address fresh = makeAddr("fresh_unused");
        PrecompileLib.AccountMarginSummary memory ms =
            PrecompileLib.accountMarginSummary(DEX_USDC_1, fresh);

        // Fresh address has never traded on HIP-3; accountMarginSummary should be zeroed.
        assertEq(ms.accountValue, 0, "fresh account value");
        assertEq(ms.marginUsed, 0, "fresh margin used");
        assertEq(ms.ntlPos, 0, "fresh ntl pos");
    }

    /// @notice After forcePerpBalance, reads should return the sim's value
    /// rather than falling through to the chain.
    function test_lazyInit_forcePerpBalanceTakesOverReads() public {
        address u = makeAddr("u_force");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 12345e6);

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), 12345e6, "forced balance should be returned");

        PrecompileLib.AccountMarginSummary memory ms =
            PrecompileLib.accountMarginSummary(DEX_USDC_1, u);
        assertEq(ms.accountValue, 12345e6, "preview summary should use forced balance");
    }

    /// @notice Activation alone does NOT inflate HIP-3 balances.
    /// Previously (buggy code) forceAccountActivation seeded perpBalance[hipDex]
    /// with accountValue from chain, which over-counted locked margin + uPnL.
    /// After the fix, activation does not touch HIP-3 balances unless the user
    /// explicitly forces one.
    function test_lazyInit_activationDoesNotSeedHip3Balance() public {
        address u = makeAddr("u_activation_only");
        CoreSimulatorLib.forceAccountActivation(u);

        // We haven't forced a HIP-3 balance; reads must fall through to real chain.
        // For a fresh address the chain returns zero.
        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), 0, "no sim-side inflation");
        assertEq(hyperCore.readPerpBalance(u, DEX_USDH_2), 0, "no sim-side inflation dex 2");
        assertEq(hyperCore.readPerpBalance(u, DEX_USDE_4), 0, "no sim-side inflation dex 4");
    }

    /// @notice Default dex (0) is unaffected by the HIP-3 changes.
    function test_lazyInit_defaultDexUnaffected() public {
        address u = makeAddr("u_default_dex");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, 1000e6); // default dex overload

        assertEq(PrecompileLib.withdrawable(u), 1000e6, "default dex withdrawable");
        assertEq(hyperCore.readPerpBalance(u, DEX_DEFAULT), 1000e6, "default dex balance");
        assertEq(hyperCore.readPerpBalance(u), 1000e6, "default overload");
    }

    /*//////////////////////////////////////////////////////////////
                       HIP-3 PERP TRADING — NVDA
    //////////////////////////////////////////////////////////////*/

    function test_hip3Trading_longOpensAndMarginReflects() public {
        address u = makeAddr("u_hip3_long");
        CoreSimulatorLib.setRevertOnFailure(true);

        vm.startPrank(u);
        HypeTradingContract trader = new HypeTradingContract(u);
        vm.stopPrank();

        CoreSimulatorLib.forceAccountActivation(address(trader));
        CoreSimulatorLib.forcePerpBalance(address(trader), DEX_USDC_1, 10_000e6);
        CoreSimulatorLib.forcePerpLeverage(address(trader), NVDA_PERP_INDEX, 5);

        uint64 startingPrice = 100_00000; // $100 with 6 dec price
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, startingPrice);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, true, 1e18, 1e8, false, 1); // buy 1 NVDA
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory pos =
            PrecompileLib.position(address(trader), NVDA_PERP_INDEX);
        assertGt(pos.szi, 0, "should have positive NVDA position");
        assertGt(pos.entryNtl, 0, "entry notional should be set");

        // Margin summary on HIP-3 dex must reflect the position.
        PrecompileLib.AccountMarginSummary memory ms =
            PrecompileLib.accountMarginSummary(DEX_USDC_1, address(trader));
        assertGt(ms.ntlPos, 0, "notional position > 0");
        assertGt(ms.marginUsed, 0, "margin used > 0");
    }

    function test_hip3Trading_shortOpens() public {
        address u = makeAddr("u_hip3_short");
        CoreSimulatorLib.setRevertOnFailure(true);

        vm.startPrank(u);
        HypeTradingContract trader = new HypeTradingContract(u);
        vm.stopPrank();

        CoreSimulatorLib.forceAccountActivation(address(trader));
        CoreSimulatorLib.forcePerpBalance(address(trader), DEX_USDC_1, 10_000e6);
        CoreSimulatorLib.forcePerpLeverage(address(trader), NVDA_PERP_INDEX, 5);

        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, 100_00000);
        CoreSimulatorLib.setPerpMakerFee(0);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, false, 0, 1e8, false, 1); // short 1 NVDA
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory pos =
            PrecompileLib.position(address(trader), NVDA_PERP_INDEX);
        assertLt(pos.szi, 0, "should have short NVDA position");
    }

    function test_hip3Trading_profitOnLong() public {
        address u = makeAddr("u_hip3_profit");
        CoreSimulatorLib.setRevertOnFailure(true);
        CoreSimulatorLib.setPerpMakerFee(0);

        vm.startPrank(u);
        HypeTradingContract trader = new HypeTradingContract(u);
        vm.stopPrank();

        CoreSimulatorLib.forceAccountActivation(address(trader));
        uint64 initialBal = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(address(trader), DEX_USDC_1, initialBal);
        CoreSimulatorLib.forcePerpLeverage(address(trader), NVDA_PERP_INDEX, 5);

        uint64 startPx = 100_00000;
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, startPx);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, true, 1e18, 1e8, false, 1);
        CoreSimulatorLib.nextBlock();

        // Price up 20%
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, startPx * 12 / 10);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, false, 0, 1e8, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 finalBal = hyperCore.readPerpBalance(address(trader), DEX_USDC_1);
        assertGt(finalBal, initialBal, "should have profit from 20% price increase on long");
    }

    function test_hip3Trading_lossOnLong() public {
        address u = makeAddr("u_hip3_loss");
        CoreSimulatorLib.setRevertOnFailure(true);
        CoreSimulatorLib.setPerpMakerFee(0);

        vm.startPrank(u);
        HypeTradingContract trader = new HypeTradingContract(u);
        vm.stopPrank();

        CoreSimulatorLib.forceAccountActivation(address(trader));
        uint64 initialBal = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(address(trader), DEX_USDC_1, initialBal);
        CoreSimulatorLib.forcePerpLeverage(address(trader), NVDA_PERP_INDEX, 5);

        uint64 startPx = 100_00000;
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, startPx);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, true, 1e18, 1e8, false, 1);
        CoreSimulatorLib.nextBlock();

        // Price down 5%
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, startPx * 95 / 100);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, false, 0, 1e8, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 finalBal = hyperCore.readPerpBalance(address(trader), DEX_USDC_1);
        assertLt(finalBal, initialBal, "should realize loss from 5% price decrease on long");
    }

    function test_hip3Trading_closePositionReturnsToZero() public {
        address u = makeAddr("u_hip3_close");
        CoreSimulatorLib.setRevertOnFailure(true);
        CoreSimulatorLib.setPerpMakerFee(0);

        vm.startPrank(u);
        HypeTradingContract trader = new HypeTradingContract(u);
        vm.stopPrank();

        CoreSimulatorLib.forceAccountActivation(address(trader));
        CoreSimulatorLib.forcePerpBalance(address(trader), DEX_USDC_1, 10_000e6);
        CoreSimulatorLib.forcePerpLeverage(address(trader), NVDA_PERP_INDEX, 5);
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, 100_00000);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, true, 1e18, 1e8, false, 1);
        CoreSimulatorLib.nextBlock();

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, false, 0, 1e8, false, 2);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory pos =
            PrecompileLib.position(address(trader), NVDA_PERP_INDEX);
        assertEq(pos.szi, 0, "position should be fully closed");
    }

    /*//////////////////////////////////////////////////////////////
              HIP-3 ISOLATION FROM DEFAULT DEX BOOKKEEPING
    //////////////////////////////////////////////////////////////*/

    /// @notice A HIP-3 trade must not affect default-dex balance.
    function test_isolation_hip3TradeDoesNotTouchDefaultDex() public {
        address u = makeAddr("u_iso");
        CoreSimulatorLib.setRevertOnFailure(true);
        CoreSimulatorLib.setPerpMakerFee(0);

        vm.startPrank(u);
        HypeTradingContract trader = new HypeTradingContract(u);
        vm.stopPrank();

        uint64 defaultBal = 3_000e6;
        uint64 hip3Bal = 5_000e6;

        CoreSimulatorLib.forceAccountActivation(address(trader));
        CoreSimulatorLib.forcePerpBalance(address(trader), defaultBal);          // dex 0
        CoreSimulatorLib.forcePerpBalance(address(trader), DEX_USDC_1, hip3Bal); // dex 1
        CoreSimulatorLib.forcePerpLeverage(address(trader), NVDA_PERP_INDEX, 5);
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, 100_00000);

        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, true, 1e18, 1e8, false, 1);
        CoreSimulatorLib.nextBlock();

        // Price up 10%, close
        CoreSimulatorLib.setMarkPx(NVDA_PERP_INDEX, 110_00000);
        vm.prank(u);
        trader.createLimitOrder(NVDA_ASSET_ID, false, 0, 1e8, false, 2);
        CoreSimulatorLib.nextBlock();

        assertEq(
            hyperCore.readPerpBalance(address(trader), DEX_DEFAULT),
            defaultBal,
            "default dex untouched by HIP-3 trade"
        );
        assertGt(
            hyperCore.readPerpBalance(address(trader), DEX_USDC_1),
            hip3Bal,
            "HIP-3 dex balance grew from profit"
        );
    }

    /// @notice Two HIP-3 dexes sharing the same quote token must remain independent.
    function test_isolation_perDexBookkeeping() public {
        address u = makeAddr("u_iso2");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 111e6);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_6, 222e6);

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), 111e6);
        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_6), 222e6);

        // Move 50 from dex 1 → dex 6
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), DEX_USDC_1, DEX_USDC_6, USDC_TOKEN, 50e8);
        CoreSimulatorLib.nextBlock();

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), 111e6 - 50e6, "dex 1 decreased");
        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_6), 222e6 + 50e6, "dex 6 increased");
    }

    /*//////////////////////////////////////////////////////////////
                       INSUFFICIENT BALANCE
    //////////////////////////////////////////////////////////////*/

    function test_sendAsset_insufficientPerpBalanceReverts() public {
        address u = makeAddr("u_insufficient");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forcePerpBalance(u, DEX_USDC_1, 10e6); // only 10 USDC

        uint64 perpBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);
        uint64 spotBefore = PrecompileLib.spotBalance(u, USDC_TOKEN).total;

        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), DEX_USDC_1, HLConstants.SPOT_DEX, USDC_TOKEN, 100e8);
        CoreSimulatorLib.nextBlock();

        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), perpBefore, "perp unchanged");
        assertEq(PrecompileLib.spotBalance(u, USDC_TOKEN).total, spotBefore, "spot unchanged");
    }

    function test_sendAsset_insufficientSpotBalanceReverts() public {
        address u = makeAddr("u_insufficient_spot");
        CoreSimulatorLib.forceAccountActivation(u);
        CoreSimulatorLib.forceSpotBalance(u, USDC_TOKEN, 5e8); // only 5 USDC wei

        uint64 spotBefore = PrecompileLib.spotBalance(u, USDC_TOKEN).total;
        uint64 perpBefore = hyperCore.readPerpBalance(u, DEX_USDC_1);

        vm.prank(u);
        CoreWriterLib.sendAsset(u, address(0), HLConstants.SPOT_DEX, DEX_USDC_1, USDC_TOKEN, 100e8);
        CoreSimulatorLib.nextBlock();

        assertEq(PrecompileLib.spotBalance(u, USDC_TOKEN).total, spotBefore, "spot unchanged");
        assertEq(hyperCore.readPerpBalance(u, DEX_USDC_1), perpBefore, "perp unchanged");
    }

    /*//////////////////////////////////////////////////////////////
                           HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Bridge USDC to Core for a test user. Handles the activation fee
    /// that the simulator deducts on first bridge to an unactivated account.
    function _bridgeUsdcToCore(address user, uint256 evmAmount) internal {
        deal(USDC_EVM, user, evmAmount);
        vm.startPrank(user);
        CoreWriterLib.bridgeToCore(USDC_EVM, evmAmount);
        vm.stopPrank();
        CoreSimulatorLib.nextBlock();
    }
}
