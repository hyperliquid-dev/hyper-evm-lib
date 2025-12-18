// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {HLConversions} from "../../../src/common/HLConversions.sol";
import {HLConstants} from "../../../src/common/HLConstants.sol";
import {HyperCore} from "../../simulation/HyperCore.sol";
import {HypeTradingContract} from "../../utils/HypeTradingContract.sol";
import {CoreSimulatorLib} from "../../simulation/CoreSimulatorLib.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";

contract PerpTradingTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    // Perp indices
    uint16 public constant BTC_PERP = 0;
    uint16 public constant ETH_PERP = 1;
    uint16 public constant HYPE_PERP = 159;
    uint16 public constant SOL_PERP = 4; // SOL perp index

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    function setUp() public {
        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        CoreSimulatorLib.forceAccountActivation(user);
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC PERP TRADING TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpTradingBasic() public {
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 1e18);

        hypeTrading.createLimitOrder(5, true, 1e18, 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), 5);
        assertEq(position.szi, 1e2, "Position size should match");

        // Short to close
        hypeTrading.createLimitOrder(5, false, 0, 1e9, false, 2);

        CoreSimulatorLib.setMarkPx(5, 2000, true); // Increase price by 20%

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), 5);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        assertGt(w2, 0, "Should have withdrawable balance");
    }

    function testPerpTradingProfitCalc() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;

        uint16 perp = BTC_PERP;
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, true, 1e18, 1 * 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(perp, startingPrice * 12 / 10); // 20% increase

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), perp);
        assertEq(position.szi, 1 * 1e5, "Position size should be 1 BTC");

        // Short to close
        hypeTrading.createLimitOrder(perp, false, 0, 1e8, false, 2);

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), perp);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));

        uint64 profit = w2 - 10_000e6;
        assertGt(profit, 0, "Should have profit after 20% price increase on long");
    }

    /*//////////////////////////////////////////////////////////////
                        BTC PERP TESTS
    //////////////////////////////////////////////////////////////*/

    function testBTCPerpLong() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1 * 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, 1 * 100_000, "Should have 1 BTC long position");
        assertGt(position.entryNtl, 0, "Entry notional should be set");
    }

    function testBTCPerpShort() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        uint64 initialPerpBalance = 5000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 9 / 10); // 10% decrease

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, -1 * 100_000, "Should have -1 BTC short position");

        // Close position
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e8, false, 2);

        CoreSimulatorLib.nextBlock();

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        uint64 profit = w2 - initialPerpBalance;
        assertGt(profit, 0, "Should have profit on short when price decreases");
    }

    function testBTCPerpLongAccountMarginSummary() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1 * 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.AccountMarginSummary memory marginSummary0 =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        assertGt(marginSummary0.ntlPos, 0, "Notional position should be > 0");

        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 12 / 10);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, 1 * 100_000, "Position size should be 1 BTC");

        PrecompileLib.AccountMarginSummary memory marginSummary =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        assertGt(marginSummary.accountValue, marginSummary0.accountValue, "Account value should increase with price");

        // Close position
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e8, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        uint64 profit = w2 - 10_000e6;
        assertGt(profit, 0, "Should have 20% profit");
    }

    /*//////////////////////////////////////////////////////////////
                        ETH PERP TESTS
    //////////////////////////////////////////////////////////////*/

    function testETHPerpLong() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 5_000e6);

        uint64 startingPrice = 400000; // $4000 for ETH
        CoreSimulatorLib.setMarkPx(ETH_PERP, startingPrice);

        hypeTrading.createLimitOrder(ETH_PERP, true, 1e18, 1 * 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), ETH_PERP);
        assertGt(position.szi, 0, "Should have positive position");
    }

    function testETHPerpShort() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 5_000e6);

        uint64 startingPrice = 400000;
        CoreSimulatorLib.setMarkPx(ETH_PERP, startingPrice);

        hypeTrading.createLimitOrder(ETH_PERP, false, 0, 1e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), ETH_PERP);
        assertLt(position.szi, 0, "Should have negative (short) position");
    }

    /*//////////////////////////////////////////////////////////////
                        HYPE PERP TESTS
    //////////////////////////////////////////////////////////////*/

    function testHYPEPerpLong() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 5_000e6);
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), HYPE_PERP, 10);

        uint64 startingPrice = 2500; // $25 for HYPE
        CoreSimulatorLib.setMarkPx(HYPE_PERP, startingPrice);

        hypeTrading.createLimitOrder(HYPE_PERP, true, 1e18, 100e8, false, 1); // 100 HYPE

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), HYPE_PERP);
        assertGt(position.szi, 0, "Should have positive HYPE position");
    }

    function testHYPEPerpShort() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 5_000e6);
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), HYPE_PERP, 10);

        uint64 startingPrice = 2500;
        CoreSimulatorLib.setMarkPx(HYPE_PERP, startingPrice);

        hypeTrading.createLimitOrder(HYPE_PERP, false, 0, 100e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), HYPE_PERP);
        assertLt(position.szi, 0, "Should have negative HYPE position");
    }

    /*//////////////////////////////////////////////////////////////
                        SOL PERP TESTS
    //////////////////////////////////////////////////////////////*/

    function testSOLPerpLong() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 5_000e6);

        uint64 startingPrice = 20000; // $200 for SOL
        CoreSimulatorLib.setMarkPx(SOL_PERP, startingPrice);

        hypeTrading.createLimitOrder(SOL_PERP, true, 1e18, 10e8, false, 1); // 10 SOL

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), SOL_PERP);
        assertGt(position.szi, 0, "Should have positive SOL position");
    }

    function testSOLPerpShort() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 5_000e6);

        uint64 startingPrice = 20000;
        CoreSimulatorLib.setMarkPx(SOL_PERP, startingPrice);

        hypeTrading.createLimitOrder(SOL_PERP, false, 0, 10e8, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), SOL_PERP);
        assertLt(position.szi, 0, "Should have negative SOL position");
    }

    /*//////////////////////////////////////////////////////////////
                        MARGIN SUMMARY TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpMarginSummaryMultiplePositions() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 20e6);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 0.00025 * 1e8, false, 1);
        hypeTrading.createLimitOrder(ETH_PERP, false, 1, 0.0044 * 1e8, false, 2);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.AccountMarginSummary memory marginSummary =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        assertGt(marginSummary.ntlPos, 0, "Should have notional position");
        assertGt(marginSummary.marginUsed, 0, "Should have margin used");
    }

    /*//////////////////////////////////////////////////////////////
                        SHORT THEN LONG TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpShortThenLong() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");

        uint64 initialPerpBalance = 5000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Short 1 BTC
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e8, false, 1);
        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 9 / 10);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, -1 * 100_000, "Should have -1 BTC");

        // Go long 2 BTC (flip position)
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 2e8, false, 2);
        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Go short 1 BTC to close
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e8, false, 3);
        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        uint64 profit = w2 - initialPerpBalance;
        assertGt(profit, 0, "Should have net profit from the trades");
    }

    /*//////////////////////////////////////////////////////////////
                        LOSS CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpLoss() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");

        uint64 initialPerpBalance = 5000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Short 1 BTC
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e8, false, 1);
        CoreSimulatorLib.nextBlock();

        // Price increases by 1% (loss for short)
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 101 / 100);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, -1 * 100_000, "Should have -1 BTC short");

        CoreSimulatorLib.nextBlock();

        // Close position if still open
        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        if (position.szi != 0) {
            hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e8, false, 2);
        }

        CoreSimulatorLib.nextBlock();

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));

        uint64 loss = initialPerpBalance - w2;
        uint256 lossPercentage = loss * 100 / initialPerpBalance;
        assertEq(lossPercentage, 20, "1% price move against short with 20x leverage = 20% loss");
    }

    /*//////////////////////////////////////////////////////////////
                        LEVERAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpDifferentLeverageLevels() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        // Test with 5x leverage
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), HYPE_PERP, 5);

        uint64 startingPrice = 2500;
        CoreSimulatorLib.setMarkPx(HYPE_PERP, startingPrice);

        hypeTrading.createLimitOrder(HYPE_PERP, true, 1e18, 100e8, false, 1);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), HYPE_PERP);
        assertGt(position.szi, 0, "Should have position with 5x leverage");
        assertEq(position.leverage, 5, "Leverage should be 5x");
    }

    /*//////////////////////////////////////////////////////////////
                        REDUCE ONLY TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpReduceOnlyOrder() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Open long position (0.1 BTC = 0.1e8 = 1e7 in order size)
        uint64 orderSize = 1e7; // 0.1 BTC
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, orderSize, false, 1);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        int64 initialSize = position.szi;
        assertGt(initialSize, 0, "Should have long position");

        // Close position with the same size
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, orderSize, false, 2);
        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, 0, "Position should be closed");
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpLiquidationOnLong() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        // Minimum margin for position
        uint64 initialPerpBalance = 500e6; // $500
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000; // $10,000
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), BTC_PERP, 20); // 20x leverage

        // Open a long position with high leverage (0.1 BTC = $1000 notional at $10k)
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1); // 0.1 BTC
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Should have long position");

        // Price drops 10% - should trigger liquidation
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 90 / 100);
        CoreSimulatorLib.nextBlock();

        // After liquidation, position should be closed and balance zeroed
        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, 0, "Position should be liquidated");

        uint64 balanceAfter = PrecompileLib.withdrawable(address(hypeTrading));
        assertEq(balanceAfter, 0, "Balance should be 0 after liquidation");
    }

    function testPerpLiquidationOnShort() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        uint64 initialPerpBalance = 500e6; // $500
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000; // $10,000
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), BTC_PERP, 20);

        // Open a short position
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e7, false, 1); // 0.1 BTC
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertLt(position.szi, 0, "Should have short position");

        // Price rises 10% - should trigger liquidation
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 110 / 100);
        CoreSimulatorLib.nextBlock();

        // After liquidation, position should be closed
        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertEq(position.szi, 0, "Position should be liquidated");
    }

    function testPerpNoLiquidationWithSufficientMargin() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        // Large margin buffer
        uint64 initialPerpBalance = 50_000e6; // $50,000
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000; // $10,000
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), BTC_PERP, 5); // Conservative 5x leverage

        // Open a small long position
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1); // 0.1 BTC
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Should have long position");

        // Price drops 10% - should NOT liquidate due to sufficient margin
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 90 / 100);
        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Position should NOT be liquidated");
    }

    /*//////////////////////////////////////////////////////////////
                        MAX LEVERAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpMaxLeverageBTC() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        // Set max leverage (BTC typically allows up to 50x)
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), BTC_PERP, 50);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Should have position with max leverage");
        assertEq(position.leverage, 50, "Leverage should be 50x");
    }

    function testPerpLowLeverage() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        // Set low leverage
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), BTC_PERP, 2);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Should have position with 2x leverage");
        assertEq(position.leverage, 2, "Leverage should be 2x");
    }

    /*//////////////////////////////////////////////////////////////
                        FEE VARIATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpWithHighFees() public {
        // Set high perp maker fee (5%)
        CoreSimulatorLib.setPerpMakerFee(500);
        CoreSimulatorLib.setRevertOnFailure(true);

        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        uint64 initialBalance = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        // Balance should be reduced by fee
        uint64 balanceAfterTrade = PrecompileLib.withdrawable(address(hypeTrading));
        assertLt(balanceAfterTrade, initialBalance, "Balance should be reduced by fees");

        // Reset fee
        CoreSimulatorLib.setPerpMakerFee(150);
    }

    function testPerpWithZeroFees() public {
        // Set zero perp maker fee
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);

        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        uint64 initialBalance = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);
        CoreSimulatorLib.forcePerpLeverage(address(hypeTrading), BTC_PERP, 20);

        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        // Close position at same price
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e7, false, 2);
        CoreSimulatorLib.nextBlock();

        // With zero fees and same entry/exit price, balance should be unchanged
        uint64 finalBalance = PrecompileLib.withdrawable(address(hypeTrading));
        assertEq(finalBalance, initialBalance, "Balance should be unchanged with zero fees");

        // Reset fee
        CoreSimulatorLib.setPerpMakerFee(150);
    }

    /*//////////////////////////////////////////////////////////////
                        POSITION FLIP TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpFlipLongToShort() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Open long 0.1 BTC
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Should have long position");

        // Sell 0.2 BTC to flip from long to short
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 2e7, false, 2);
        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertLt(position.szi, 0, "Should have flipped to short position");
    }

    function testPerpFlipShortToLong() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Open short 0.1 BTC
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertLt(position.szi, 0, "Should have short position");

        // Buy 0.2 BTC to flip from short to long
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 2e7, false, 2);
        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        assertGt(position.szi, 0, "Should have flipped to long position");
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE POSITIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpMultipleAssetsSimultaneously() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 50_000e6);

        // Set prices
        CoreSimulatorLib.setMarkPx(BTC_PERP, 1000000);
        CoreSimulatorLib.setMarkPx(ETH_PERP, 400000);
        CoreSimulatorLib.setMarkPx(SOL_PERP, 20000);

        // Open positions on multiple perps
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1); // Long BTC
        hypeTrading.createLimitOrder(ETH_PERP, false, 0, 1e8, false, 2);   // Short ETH
        hypeTrading.createLimitOrder(SOL_PERP, true, 1e18, 10e8, false, 3); // Long SOL

        CoreSimulatorLib.nextBlock();

        // Verify all positions exist
        PrecompileLib.Position memory btcPos = hypeTrading.getPosition(address(hypeTrading), BTC_PERP);
        PrecompileLib.Position memory ethPos = hypeTrading.getPosition(address(hypeTrading), ETH_PERP);
        PrecompileLib.Position memory solPos = hypeTrading.getPosition(address(hypeTrading), SOL_PERP);

        assertGt(btcPos.szi, 0, "Should have long BTC position");
        assertLt(ethPos.szi, 0, "Should have short ETH position");
        assertGt(solPos.szi, 0, "Should have long SOL position");

        // Check margin summary reflects all positions
        PrecompileLib.AccountMarginSummary memory summary = hypeTrading.getAccountMarginSummary(address(hypeTrading));
        assertGt(summary.ntlPos, 0, "Total notional should be > 0");
        assertGt(summary.marginUsed, 0, "Margin used should be > 0");
    }

    /*//////////////////////////////////////////////////////////////
                        EXTREME PRICE MOVEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testPerpLargePriceIncrease() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        uint64 initialBalance = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Open long
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        // 50% price increase
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 150 / 100);

        // Close position
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e7, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 finalBalance = PrecompileLib.withdrawable(address(hypeTrading));
        assertGt(finalBalance, initialBalance, "Should have significant profit from 50% price increase");
    }

    function testPerpSmallPriceMovement() public {
        CoreSimulatorLib.setPerpMakerFee(0);
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));

        uint64 initialBalance = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialBalance);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Open long
        hypeTrading.createLimitOrder(BTC_PERP, true, 1e18, 1e7, false, 1);
        CoreSimulatorLib.nextBlock();

        // 0.1% price increase (10 bps)
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice * 10010 / 10000);

        // Close position
        hypeTrading.createLimitOrder(BTC_PERP, false, 0, 1e7, false, 2);
        CoreSimulatorLib.nextBlock();

        uint64 finalBalance = PrecompileLib.withdrawable(address(hypeTrading));
        // Small profit expected
        assertGe(finalBalance, initialBalance, "Should have small profit from 0.1% price increase");
    }
}
