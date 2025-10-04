// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../src/PrecompileLib.sol";
import {HLConversions} from "../src/common/HLConversions.sol";
import {HLConstants} from "../src/common/HLConstants.sol";
import {BridgingExample} from "../src/examples/BridgingExample.sol";
import {HyperCore} from "./simulation/HyperCore.sol";
import {L1Read} from "./utils/L1Read.sol";
import {HypeTradingContract} from "./utils/HypeTradingContract.sol";
import {CoreSimulatorLib} from "./simulation/CoreSimulatorLib.sol";
import {RealL1Read} from "./utils/RealL1Read.sol";
import {CoreWriterLib} from "../src/CoreWriterLib.sol";
import {VaultExample} from "../src/examples/VaultExample.sol";
import {StakingExample} from "../src/examples/StakingExample.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CoreSimulatorTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant uBTC = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463;
    address public constant uETH = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;
    address public constant uSOL = 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    BridgingExample public bridgingExample;

    L1Read l1Read;

    function setUp() public {
        //string memory hyperliquidRpc = "https://rpc.hyperliquid.xyz/evm";
        //string memory archiveRpc = "https://rpc.purroofgroup.com";

        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        // set up the HyperCore simulation
        hyperCore = CoreSimulatorLib.init();

        bridgingExample = new BridgingExample();

        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(address(bridgingExample));

        l1Read = new L1Read();
    }

    function test_bridgeHypeToCore() public {
        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreById{value: 1e18}(150, 1e18);

        (uint64 total, uint64 hold, uint64 entryNtl) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);
    }

    function test_l1Read() public {
        uint64 px = RealL1Read.spotPx(uint32(107));
        console.log("px", px);
    }

    function test_bridgeToCoreAndSend() public {
        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreAndSendHype{value: 1e18}(1e18, address(user));

        (uint64 total, uint64 hold, uint64 entryNtl) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(user), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(user), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);
    }

    function test_listDeployers() public {
        PrecompileLib.TokenInfo memory data = RealL1Read.tokenInfo(uint32(350));
        console.log("deployer", data.deployer);
        console.log("name", data.name);
        console.log("szDecimals", data.szDecimals);
        console.log("weiDecimals", data.weiDecimals);
        console.log("evmExtraWeiDecimals", data.evmExtraWeiDecimals);
        console.log("evmContract", data.evmContract);
        console.log("deployerTradingFeeShare", data.deployerTradingFeeShare);
    }

    // This checks that existing spot balances are accounted for in tests
    function test_bridgeToCoreAndSendToExistingUser() public {
        address recipient = 0x68e7E72938db36a5CBbCa7b52c71DBBaaDfB8264;

        deal(address(user), 10000e18);

        uint256 amountToSend = 1e18;

        vm.startPrank(user);
        bridgingExample.bridgeToCoreAndSendHype{value: amountToSend}(amountToSend, address(recipient));

        (uint64 realTotal,,) =
            abi.decode(abi.encode(RealL1Read.spotBalance(address(recipient), 150)), (uint64, uint64, uint64));
        console.log("realTotal", realTotal);

        (uint64 precompileTotal,,) =
            abi.decode(abi.encode(l1Read.spotBalance(address(recipient), 150)), (uint64, uint64, uint64));
        console.log("precompileTotal", precompileTotal);

        CoreSimulatorLib.nextBlock();

        (uint64 newTotal,,) =
            abi.decode(abi.encode(l1Read.spotBalance(address(recipient), 150)), (uint64, uint64, uint64));
        console.log("total", newTotal);
        console.log("rhs:", realTotal + HLConversions.evmToWei(150, amountToSend));
        assertEq(newTotal, realTotal + HLConversions.evmToWei(150, amountToSend));
    }

    function test_bridgeEthToCore() public {
        deal(address(uETH), address(bridgingExample), 1e18);

        bridgingExample.bridgeToCoreById(221, 1e18);

        (uint64 total, uint64 hold, uint64 entryNtl) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 221)), (uint64, uint64, uint64));
        console.log("total", total);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 221)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);
    }

    function test_readDelegations() public {
        PrecompileLib.Delegation[] memory delegations =
            RealL1Read.delegations(address(0x393D0B87Ed38fc779FD9611144aE649BA6082109));
        console.log("delegations", delegations.length);

        uint256 totalDelegated = 0;

        for (uint256 i = 0; i < delegations.length; i++) {
            console.log("delegation validator:", delegations[i].validator);
            console.log("delegation amount:", delegations[i].amount);
            console.log("locked until:", delegations[i].lockedUntilTimestamp);
            totalDelegated += delegations[i].amount;
        }

        console.log("totalDelegated", totalDelegated);
    }

    function test_readDelegatorSummary() public {
        PrecompileLib.DelegatorSummary memory summary =
            RealL1Read.delegatorSummary(address(0x393D0B87Ed38fc779FD9611144aE649BA6082109));
        console.log("summary.delegated", summary.delegated);
        console.log("summary.undelegated", summary.undelegated);
        console.log("summary.totalPendingWithdrawal", summary.totalPendingWithdrawal);
        console.log("summary.nPendingWithdrawals", summary.nPendingWithdrawals);
    }

    function test_spotPrice() public {
        uint64 px = RealL1Read.spotPx(uint32(123));
        console.log("px", px);
    }

    function test_perpTrading() public {
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 1e18);

        hypeTrading.createLimitOrder(5, true, 1e18, 1e2, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), 5);
        assertEq(position.szi, 1e2);

        // short for 1e3
        hypeTrading.createLimitOrder(5, false, 0, 1e3, false, 2);

        // increase price by 20%
        CoreSimulatorLib.setMarkPx(5, 2000, true);

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), 5);
        console.log("position.entryNtl", position.entryNtl);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w2);

        // long uSOL
        hypeTrading.createLimitOrder(5, true, 1e18, 1e2, false, 3);
        hypeTrading.createLimitOrder(5, true, 1e18, 1e5, false, 4);

        CoreSimulatorLib.nextBlock();
    }

    function test_perpTrading_profitCalc() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;

        uint16 perp = 0; // btc
        console.log("btc mark px is %e", PrecompileLib.markPx(perp));
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, true, 1e18, 1 * 100_000, false, 1);

        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(perp, startingPrice * 12 / 10);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), perp);
        assertEq(position.szi, 1 * 100_000);

        // short for same sz
        hypeTrading.createLimitOrder(perp, false, 0, 1 * 100_000, false, 2);

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), perp);
        console.log("position.entryNtl", position.entryNtl);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w2);

        uint64 profit = w2 - 10_000e6;
        console.log("profit: %e", profit);

        console.log("profit percentage: ", profit * 100 / 10_000e6);
    }

    function test_1_BTC_Long_AccountMarginSummaryTest() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 10_000e6);

        uint64 startingPrice = 1000000;

        uint16 perp = 0; // btc
        console.log("btc mark px is %e", PrecompileLib.markPx(perp));
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, true, 1e18, 1 * 100_000, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.AccountMarginSummary memory marginSummary0 =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        console.log("marginSummary.accountValue %e", marginSummary0.accountValue);
        console.log("marginSummary.marginUsed %e", marginSummary0.marginUsed);
        console.log("marginSummary.ntlPos %e", marginSummary0.ntlPos);
        console.log("marginSummary.rawUsd %e", marginSummary0.rawUsd);

        uint64 w0 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable %e", w0);

        CoreSimulatorLib.setMarkPx(perp, startingPrice * 12 / 10);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), perp);
        assertEq(position.szi, 1 * 100_000);

        PrecompileLib.AccountMarginSummary memory marginSummary =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        console.log("marginSummary.accountValue %e", marginSummary.accountValue);
        console.log("marginSummary.marginUsed %e", marginSummary.marginUsed);
        console.log("marginSummary.ntlPos %e", marginSummary.ntlPos);
        console.log("marginSummary.rawUsd %e", marginSummary.rawUsd);

        uint64 w1 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable %e", w1);

        // short for same sz
        hypeTrading.createLimitOrder(perp, false, 0, 1 * 100_000, false, 2);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position2 = hypeTrading.getPosition(address(hypeTrading), perp);
        console.log("position2.szi %e", position2.szi);

        PrecompileLib.AccountMarginSummary memory marginSummary2 =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        console.log("marginSummary2.accountValue %e", marginSummary2.accountValue);
        console.log("marginSummary2.marginUsed %e", marginSummary2.marginUsed);
        console.log("marginSummary2.ntlPos %e", marginSummary2.ntlPos);
        console.log("marginSummary2.rawUsd %e", marginSummary2.rawUsd);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable %e", w2);

        uint64 profit = w2 - 10_000e6;
        console.log("profit: %e", profit);

        console.log("profit percentage: ", profit * 100 / 10_000e6);
    }

    function test_margin_summary() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), 20e6);

        uint16 perpBTC = 0;
        uint16 perpETH = 1;

        hypeTrading.createLimitOrder(perpBTC, true, 1e18, 0.00025 * 100_000, false, 1);
        hypeTrading.createLimitOrder(perpETH, false, 1, 0.0044 * 100_00, false, 2);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.AccountMarginSummary memory marginSummary =
            hypeTrading.getAccountMarginSummary(address(hypeTrading));
        console.log("marginSummary.accountValue %e", marginSummary.accountValue);
        console.log("marginSummary.marginUsed %e", marginSummary.marginUsed);
        console.log("marginSummary.ntlPos %e", marginSummary.ntlPos);
        console.log("marginSummary.rawUsd %e", marginSummary.rawUsd);

        uint64 w1 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable %e", w1);
    }

    function test_short() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");

        uint64 initialPerpBalance = 5000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000;

        uint16 perp = 0; // btc
        console.log("btc mark px is %e", PrecompileLib.markPx(perp));
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, false, 0, 1 * 100_000, false, 1);

        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(perp, startingPrice * 9 / 10);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), perp);
        assertEq(position.szi, -1 * 100_000);

        // short for same sz
        hypeTrading.createLimitOrder(perp, true, 1e18, 1 * 100_000, false, 2);

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), perp);
        console.log("position.entryNtl", position.entryNtl);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w2);

        uint64 profit = w2 - initialPerpBalance;
        console.log("profit: %e", profit);

        console.log("profit percentage: ", profit * 100 / initialPerpBalance);
    }

    function test_shortThenLong() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");

        uint64 initialPerpBalance = 5000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000;

        uint16 perp = 0; // btc
        console.log("btc mark px is %e", PrecompileLib.markPx(perp));
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, false, 0, 1 * 100_000, false, 1);

        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(perp, startingPrice * 9 / 10);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), perp);
        assertEq(position.szi, -1 * 100_000);

        //
        hypeTrading.createLimitOrder(perp, true, 1e18, 2 * 100_000, false, 2);

        CoreSimulatorLib.nextBlock();
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, false, 0, 1 * 100_000, false, 3);

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), perp);
        console.log("position.entryNtl", position.entryNtl);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w2);

        uint64 profit = w2 - initialPerpBalance;
        console.log("profit: %e", profit);

        console.log("profit percentage: ", profit * 100 / initialPerpBalance);
    }

    function test_loss() public {
        CoreSimulatorLib.setRevertOnFailure(true);
        vm.startPrank(user);
        HypeTradingContract hypeTrading = new HypeTradingContract(address(user));
        CoreSimulatorLib.forceAccountActivation(address(hypeTrading));
        vm.label(address(hypeTrading), "hypeTrading");

        uint64 initialPerpBalance = 5000e6;
        CoreSimulatorLib.forcePerpBalance(address(hypeTrading), initialPerpBalance);

        uint64 startingPrice = 1000000;

        uint16 perp = 0; // btc
        console.log("btc mark px is %e", PrecompileLib.markPx(perp));
        CoreSimulatorLib.setMarkPx(perp, startingPrice);

        hypeTrading.createLimitOrder(perp, false, 0, 1 * 100_000, false, 1);

        CoreSimulatorLib.nextBlock();

        CoreSimulatorLib.setMarkPx(perp, startingPrice * 101 / 100);

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), perp);
        assertEq(position.szi, -1 * 100_000);

        CoreSimulatorLib.nextBlock();

        // close pos
        position = hypeTrading.getPosition(address(hypeTrading), perp);
        if (position.szi != 0) {
            hypeTrading.createLimitOrder(perp, true, 1e18, 1 * 100_000, false, 2);
        }

        CoreSimulatorLib.nextBlock();

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w2);

        uint64 loss = initialPerpBalance - w2;

        uint256 lossPercentage = loss * 100 / initialPerpBalance;
        assertEq(lossPercentage, 20);
    }

    function test_spotTrading() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 0, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        spotTrader.placeLimitOrder(10000 + 156, true, 1e18, 1e2, false, 1);

        // log spot balance of spotTrader
        console.log("spotTrader.spotBalance(254)", PrecompileLib.spotBalance(address(spotTrader), 254).total);
        console.log("spotTrader.spotBalance(0)", PrecompileLib.spotBalance(address(spotTrader), 0).total);

        CoreSimulatorLib.nextBlock();

        console.log("spotTrader.spotBalance(254)", PrecompileLib.spotBalance(address(spotTrader), 254).total);
        console.log("spotTrader.spotBalance(0)", PrecompileLib.spotBalance(address(spotTrader), 0).total);
    }

    function test_limitOrder() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 0, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        // Log the current spot price before placing order
        uint32 spotMarketId = 156;
        uint64 currentSpotPx = PrecompileLib.spotPx(spotMarketId);
        console.log("Current spot price for market 156:", currentSpotPx);

        // Place a buy order with limit price below current spot price (won't execute immediately)
        uint64 limitPx = currentSpotPx / 2; // Set limit price below current price
        console.log("Placing buy order with limit price:", limitPx);
        console.log("Expected executeNow for buy order:", limitPx >= currentSpotPx ? "true" : "false");

        spotTrader.placeLimitOrder(10000 + spotMarketId, true, limitPx, 1e2, false, 1);

        // log spot balance of spotTrader before any execution
        console.log(
            "Before execution - spotTrader.spotBalance(254):", PrecompileLib.spotBalance(address(spotTrader), 254).total
        );
        console.log(
            "Before execution - spotTrader.spotBalance(0):", PrecompileLib.spotBalance(address(spotTrader), 0).total
        );

        CoreSimulatorLib.nextBlock();

        // Check balances after first block - order should still be pending
        console.log(
            "After first block - spotTrader.spotBalance(254):",
            PrecompileLib.spotBalance(address(spotTrader), 254).total
        );
        console.log(
            "After first block - spotTrader.spotBalance(0):", PrecompileLib.spotBalance(address(spotTrader), 0).total
        );

        // Now update the price to match the order's limit price
        console.log("Updating spot price to:", limitPx);
        CoreSimulatorLib.setSpotPx(spotMarketId, limitPx);

        CoreSimulatorLib.nextBlock();

        // Check balances after price change - order should now execute
        console.log(
            "After price update - spotTrader.spotBalance(254):",
            PrecompileLib.spotBalance(address(spotTrader), 254).total
        );
        console.log(
            "After price update - spotTrader.spotBalance(0):", PrecompileLib.spotBalance(address(spotTrader), 0).total
        );
    }

    function test_limitOrderSell() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        CoreSimulatorLib.forceAccountActivation(address(spotTrader));
        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 0, 1e18);
        CoreSimulatorLib.forceSpotBalance(address(spotTrader), 254, 1e18);

        // Log the current spot price before placing order
        uint32 spotMarketId = 156;
        uint64 currentSpotPx = PrecompileLib.spotPx(spotMarketId);
        console.log("Current spot price for market 156:", currentSpotPx);

        // Place a sell order with limit price above current spot price (won't execute immediately)
        uint64 limitPx = currentSpotPx * 2; // Set limit price above current price
        console.log("Placing sell order with limit price:", limitPx);

        spotTrader.placeLimitOrderGTC(10000 + spotMarketId, false, limitPx, 1e2, false, 1);

        // log spot balance of spotTrader before any execution
        console.log(
            "Before execution - spotTrader.spotBalance(254):", PrecompileLib.spotBalance(address(spotTrader), 254).total
        );
        console.log(
            "Before execution - spotTrader.spotBalance(0):", PrecompileLib.spotBalance(address(spotTrader), 0).total
        );

        CoreSimulatorLib.nextBlock();

        // Check balances after first block - order should still be pending
        console.log(
            "After first block - spotTrader.spotBalance(254):",
            PrecompileLib.spotBalance(address(spotTrader), 254).total
        );
        console.log(
            "After first block - spotTrader.spotBalance(0):", PrecompileLib.spotBalance(address(spotTrader), 0).total
        );

        // Now update the price to match the order's limit price
        console.log("Updating spot price to:", limitPx);
        CoreSimulatorLib.setSpotPx(spotMarketId, limitPx);

        CoreSimulatorLib.nextBlock();

        // Check balances after price change - order should now execute
        console.log(
            "After price update - spotTrader.spotBalance(254):",
            PrecompileLib.spotBalance(address(spotTrader), 254).total
        );
        console.log(
            "After price update - spotTrader.spotBalance(0):", PrecompileLib.spotBalance(address(spotTrader), 0).total
        );
    }

    function test_approveBuilderFee() public {
        vm.startPrank(user);
        BuilderFeeApprover approver = new BuilderFeeApprover();
        CoreSimulatorLib.forceAccountActivation(address(approver));

        approver.approveBuilderFee(10, user);

        approver.approveBuilderFee(type(uint64).max, USDT0);

        address zeroFeeBuilder = makeAddr("zeroFeeBuilder");
        approver.approveBuilderFee(0, zeroFeeBuilder);
    }

    function test_account_activation_fee() public {
        vm.startPrank(user);

        // Give sender 10 USDC
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceSpotBalance(user, 0, 10e8);

        address newAccount = makeAddr("newAccount");

        uint64 before = PrecompileLib.spotBalance(user, 0).total;

        // Send 2 USDC to new account
        CoreWriterLib.spotSend(newAccount, 0, 2e8);
        CoreSimulatorLib.nextBlock();

        uint64 afterBalance = PrecompileLib.spotBalance(user, 0).total;

        console.log("Before:", before);
        console.log("After:", afterBalance);
        console.log("Diff:", before - afterBalance);

        // Should deduct 3 USDC total (2 transfer + 1 creation fee)
        assertEq(before - afterBalance, 3e8, "Should deduct 2 USDC + 1 USDC creation fee");
    }

    function test_bridgeHypeToCoreAndSell() public {
        vm.startPrank(user);

        uint256 initialBalance = 10_000e18;
        uint256 amountToBridge = 10e18;
        uint64 token = 150;
        uint64 spot = PrecompileLib.getSpotIndex(150);
        deal(address(user), initialBalance);

        assertEq(address(user).balance, initialBalance);

        CoreWriterLib.bridgeToCore(token, amountToBridge);

        assertEq(address(user).balance, initialBalance - amountToBridge);
        assertEq(PrecompileLib.spotBalance(address(user), token).total, 0);

        CoreSimulatorLib.nextBlock();

        assertEq(address(user).balance, initialBalance - amountToBridge);
        assertEq(PrecompileLib.spotBalance(address(user), token).total, HLConversions.evmToWei(token, amountToBridge));

        // sell to USDC
        // log the spot price
        uint64 spotPx = PrecompileLib.spotPx(uint32(spot));
        console.log("spotPx", spotPx);

        uint256 usdcBalanceBefore = PrecompileLib.spotBalance(address(user), 0).total;

        uint64 tradeSz = token.weiToSz(token.evmToWei(amountToBridge));
        assertEq(tradeSz, 10 * 100);

        CoreWriterLib.placeLimitOrder(uint32(spot + 10000), false, 0, tradeSz, true, HLConstants.LIMIT_ORDER_TIF_IOC, 1);

        CoreSimulatorLib.nextBlock();

        uint256 usdcBalanceAfter = PrecompileLib.spotBalance(address(user), 0).total;
        uint256 hypeBalanceAfter = PrecompileLib.spotBalance(address(user), token).total;

        assertApproxEqAbs(usdcBalanceAfter - usdcBalanceBefore, tradeSz * spotPx, tradeSz * spotPx * 5 / 1000);
        assertEq(hypeBalanceAfter, 0);
    }

    function testVaultDeposit() public {
        test_bridgeHypeToCoreAndSell();

        uint64 usdcBalance = PrecompileLib.spotBalance(address(user), 0).total;
        uint64 vaultDepositAmt = HLConversions.weiToPerp(usdcBalance);
        address vault = 0xaC26Cf5F3C46B5e102048c65b977d2551B72A9c7;

        CoreWriterLib.transferUsdClass(vaultDepositAmt, true);
        CoreWriterLib.vaultTransfer(vault, true, vaultDepositAmt);

        CoreSimulatorLib.nextBlock();

        uint256 vaultBalanceAfter = PrecompileLib.userVaultEquity(address(user), vault).equity;
        assertEq(vaultBalanceAfter, vaultDepositAmt);
    }

    function test_vaultMultiplier() public {
        // Deploy VaultExample contract
        VaultExample vaultExample = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vaultExample));
        CoreSimulatorLib.forcePerpBalance(address(vaultExample), 1000e6); // Give it some perp balance

        address testVault = 0x07Fd993f0fA3A185F7207ADcCD29f7A87404689D;

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vaultExample));
        vaultExample.depositToVault(testVault, depositAmount);

        CoreSimulatorLib.nextBlock();

        // Check initial vault equity
        PrecompileLib.UserVaultEquity memory initialEquity =
            hyperCore.readUserVaultEquity(address(vaultExample), testVault);
        console.log("Initial vault equity:", initialEquity.equity);

        // Test 10% profit (1.1x multiplier)
        CoreSimulatorLib.setVaultMultiplier(testVault, 1.1e18);
        PrecompileLib.UserVaultEquity memory profitEquity =
            hyperCore.readUserVaultEquity(address(vaultExample), testVault);
        console.log("Equity with 10% profit:", profitEquity.equity);
    }

    function test_vaultDepositWithdraw() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 100e6);

        address testVault = 0x07Fd993f0fA3A185F7207ADcCD29f7A87404689D;
        uint64 depositAmount = 100e6;

        vm.startPrank(address(vault));

        vault.depositToVault(testVault, depositAmount);
        CoreSimulatorLib.nextBlock();

        // Try to withdraw before the lock period expires - should revert
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), testVault);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoreWriterLib.CoreWriterLib__StillLockedUntilTimestamp.selector, vaultEquity.lockedUntilTimestamp
            )
        );
        vault.withdrawFromVault(testVault, depositAmount);
        CoreSimulatorLib.setVaultMultiplier(testVault, 1.1e18);

        vm.warp((block.timestamp + 1 days + 1));

        vault.withdrawFromVault(testVault, depositAmount * 11 / 10);
        CoreSimulatorLib.nextBlock();

        uint256 perpBalanceAfter = PrecompileLib.withdrawable(address(vault));
        assertEq(perpBalanceAfter, depositAmount * 11 / 10);
    }

    function max(uint64 a, uint64 b) internal pure returns (uint64) {
        return a > b ? a : b;
    }
    function test_staking() public {
        uint64 HYPE = 150;
        address validator = 0xEEEe86F718F9Da3e7250624A460f6EA710E9C006;
        // deploy staking contract
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.setRevertOnFailure(true);

        console.log("user", user);
        console.log("staking", address(staking));

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        // check the delegator summary
        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, HYPE.evmToWei(1000e18));
        assertEq(summary.undelegated, 0);
        assertEq(summary.nPendingWithdrawals, 0);
        assertEq(summary.totalPendingWithdrawal, 0);

        // set staking multiplier to 1.1x
        CoreSimulatorLib.setStakingYieldIndex(1.1e18);
        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(uint256(summary.delegated), uint256(HYPE.evmToWei(1000e18)) * 1.1e18 / 1e18);
        assertEq(summary.undelegated, 0);
        assertEq(summary.nPendingWithdrawals, 0);
        assertEq(summary.totalPendingWithdrawal, 0);

        CoreSimulatorLib.setStakingYieldIndex(1e18);

        // undelegate
        staking.undelegateTokens(validator, HYPE.evmToWei(1000e18));

        CoreSimulatorLib.nextBlock();

        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, 0);
        assertEq(summary.undelegated, HYPE.evmToWei(1000e18));
        assertEq(summary.nPendingWithdrawals, 0);
        assertEq(summary.totalPendingWithdrawal, 0);

        staking.withdrawStake(HYPE.evmToWei(1000e18));
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 7 days);

        CoreSimulatorLib.nextBlock();

        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, 0);
        assertEq(summary.undelegated, 0);
        assertEq(summary.nPendingWithdrawals, 0);
        assertEq(summary.totalPendingWithdrawal, 0);


    }

    function test_staking_delegations() public {

        uint64 HYPE = 150;
        address validator = 0xEEEe86F718F9Da3e7250624A460f6EA710E9C006;
        // deploy staking contract
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.setRevertOnFailure(true);

        console.log("user", user);
        console.log("staking", address(staking));

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        // check delegations
        PrecompileLib.Delegation[] memory delegations = PrecompileLib.delegations(address(staking));
        assertEq(delegations.length, 1);
        assertEq(delegations[0].validator, validator);
        assertEq(delegations[0].amount, HYPE.evmToWei(1000e18));
        assertEq(delegations[0].lockedUntilTimestamp, block.timestamp * 1000);
    }

    function test_maxPendingWithdrawals() public {
        uint64 HYPE = 150;
        address validator = 0xEEEe86F718F9Da3e7250624A460f6EA710E9C006;
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.setRevertOnFailure(true);

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        staking.undelegateTokens(validator, HYPE.evmToWei(1000e18));

        CoreSimulatorLib.nextBlock();

        staking.withdrawStake(HYPE.evmToWei(100e18));
        staking.withdrawStake(HYPE.evmToWei(100e18));

        staking.withdrawStake(HYPE.evmToWei(100e18));

        staking.withdrawStake(HYPE.evmToWei(100e18));
        staking.withdrawStake(HYPE.evmToWei(100e18));

        CoreSimulatorLib.nextBlock();

        // should fail due to maximum of 5 pending withdrawals per account
        staking.withdrawStake(HYPE.evmToWei(50e18));

        bool expectRevert = true;
        CoreSimulatorLib.nextBlock(expectRevert);
    }

    // bridging
    function test_bridgeToEvm() public {

        // force balances on Core
        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(user), PrecompileLib.getTokenIndex(uETH), 1e15);

        vm.startPrank(address(user));
        uint256 amount = 20e18;

        CoreWriterLib.bridgeToEvm(uETH, amount);

        CoreSimulatorLib.nextBlock();

        uint256 userBalance = IERC20(uETH).balanceOf(address(user));
        assertEq(userBalance, amount);
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

contract BuilderFeeApprover {
    function approveBuilderFee(uint64 maxFeeRate, address builder) public {
        CoreWriterLib.approveBuilderFee(maxFeeRate, builder);
    }
}

// TODO:
// for perps:
//      - handle the other fields of the position
//      - handle isolated margin positions
//      - handle leverage changes (assuming theres an API wallet to do this)
// double check HYPE required on HyperCore for spotSend of non-HYPE tokens
// readAccountMarginSummary
