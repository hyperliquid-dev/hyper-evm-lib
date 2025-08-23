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

contract CoreSimulatorTest is Test {
    using PrecompileLib for address;
    using HLConversions for uint256;

    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant uBTC = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463;
    address public constant uETH = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;
    address public constant uSOL = 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    BridgingExample public bridgingExample;

    L1Read l1Read;

    function setUp() public {
        // hyperliquid RPC:
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");

        // set up the HyperCore simulation
        hyperCore = CoreSimulatorLib.init();

        bridgingExample = new BridgingExample();

        hyperCore.forceAccountCreation(user);
        hyperCore.forceAccountCreation(address(bridgingExample));

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

        (uint64 realTotal, uint64 realHold, uint64 realEntryNtl) =
            abi.decode(abi.encode(RealL1Read.spotBalance(address(recipient), 150)), (uint64, uint64, uint64));
        console.log("realTotal", realTotal);

        (uint64 precompileTotal,,) =
            abi.decode(abi.encode(l1Read.spotBalance(address(recipient), 150)), (uint64, uint64, uint64));
        console.log("precompileTotal", precompileTotal);

        CoreSimulatorLib.nextBlock();

        (uint64 newTotal, uint64 newHold, uint64 newEntryNtl) =
            abi.decode(abi.encode(l1Read.spotBalance(address(recipient), 150)), (uint64, uint64, uint64));
        console.log("total", newTotal);
        console.log("rhs:", realTotal + HLConversions.convertEvmToCoreAmount(150, amountToSend));
        assertEq(newTotal, realTotal + HLConversions.convertEvmToCoreAmount(150, amountToSend));
    }

    function test_readSpotBalance() public {
        (uint64 realTotal, uint64 realHold, uint64 realEntryNtl) =
            abi.decode(abi.encode(l1Read.spotBalance(address(user), 150)), (uint64, uint64, uint64));
        console.log("realTotal", realTotal);
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
        address kinetiq = 0x68e7E72938db36a5CBbCa7b52c71DBBaaDfB8264;
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
        address kinetiq = 0x68e7E72938db36a5CBbCa7b52c71DBBaaDfB8264;
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
        hyperCore.forceAccountCreation(address(hypeTrading));
        hyperCore.forcePerpBalance(address(hypeTrading), 1e18);

        hypeTrading.createLimitOrder(5, true, 1e18, 1e2, false, 1);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.Position memory position = hypeTrading.getPosition(address(hypeTrading), 5);
        console.log("position.szi", position.szi);
        console.log("position.entryNtl", position.entryNtl);

        // read their perp balance (withdrawable)
        uint64 w = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w);

        hypeTrading.createLimitOrder(5, false, 0, 1e2, false, 2);

        hyperCore.setMarkPx(5, 2000, true);

        CoreSimulatorLib.nextBlock();

        position = hypeTrading.getPosition(address(hypeTrading), 5);
        console.log("position.szi", position.szi);
        console.log("position.entryNtl", position.entryNtl);

        uint64 w2 = PrecompileLib.withdrawable(address(hypeTrading));
        console.log("withdrawable", w2);
    }

    function test_spotTrading() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        hyperCore.forceAccountCreation(address(spotTrader));
        hyperCore.forceAccountCreation(address(user));
        hyperCore.forceSpot(address(spotTrader), 0, 1e18);
        hyperCore.forceSpot(address(spotTrader), 254, 1e18);

        spotTrader.placeLimitOrder(10000 + 156, true, 1e18, 1e2, false, 1);

        // log spot balance of spotTrader
        console.log("spotTrader.spotBalance(254)", PrecompileLib.spotBalance(address(spotTrader), 254).total);
        console.log("spotTrader.spotBalance(0)", PrecompileLib.spotBalance(address(spotTrader), 0).total);

        CoreSimulatorLib.nextBlock();

        console.log("spotTrader.spotBalance(254)", PrecompileLib.spotBalance(address(spotTrader), 254).total);
        console.log("spotTrader.spotBalance(0)", PrecompileLib.spotBalance(address(spotTrader), 0).total);
    }

    function test_LimitOrder() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        hyperCore.forceAccountCreation(address(spotTrader));
        hyperCore.forceAccountCreation(address(user));
        hyperCore.forceSpot(address(spotTrader), 0, 1e18);
        hyperCore.forceSpot(address(spotTrader), 254, 1e18);

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
        hyperCore.setSpotPx(spotMarketId, limitPx);

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

    function test_LimitOrderSell() public {
        vm.startPrank(user);
        SpotTrader spotTrader = new SpotTrader();
        hyperCore.forceAccountCreation(address(spotTrader));
        hyperCore.forceAccountCreation(address(user));
        hyperCore.forceSpot(address(spotTrader), 0, 1e18);
        hyperCore.forceSpot(address(spotTrader), 254, 1e18);

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
        hyperCore.setSpotPx(spotMarketId, limitPx);

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

    function test_usdc_creation_fee() public {
        vm.startPrank(user);

        // Give sender 10 USDC
        hyperCore.forceAccountCreation(user);
        hyperCore.forceSpot(user, 0, 10e8);

        address newAccount = makeAddr("newAccount");

        uint64 before = hyperCore.readSpotBalance(user, 0).total;

        // Send 2 USDC to new account
        CoreWriterLib.spotSend(newAccount, 0, 2e8);
        CoreSimulatorLib.nextBlock();

        uint64 afterBalance = hyperCore.readSpotBalance(user, 0).total;

        console.log("Before:", before);
        console.log("After:", afterBalance);
        console.log("Diff:", before - afterBalance);

        // Should deduct 3 USDC total (2 transfer + 1 creation fee)
        assertEq(before - afterBalance, 3e8, "Should deduct 2 USDC + 1 USDC creation fee");
    }

    function test_multiple_actions() public {
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
        assertEq(PrecompileLib.spotBalance(address(user), token).total, HLConversions.convertEvmToCoreAmount(token, amountToBridge));


        // sell to USDC
        // log the spot price
        uint64 spotPx = PrecompileLib.spotPx(uint32(spot));
        console.log("spotPx", spotPx);

        uint256 usdcBalanceBefore = PrecompileLib.spotBalance(address(user), 0).total;

        uint64 tradeSz = 10 * 100;

        CoreWriterLib.placeLimitOrder(uint32(spot + 10000), false, 0, tradeSz, true, HLConstants.LIMIT_ORDER_TIF_IOC, 1);

        CoreSimulatorLib.nextBlock();

        uint256 usdcBalanceAfter = PrecompileLib.spotBalance(address(user), 0).total;
        uint256 hypeBalanceAfter = PrecompileLib.spotBalance(address(user), token).total;

        assertApproxEqAbs(usdcBalanceAfter - usdcBalanceBefore, tradeSz * spotPx, tradeSz * spotPx * 5 / 1000);
        assertEq(hypeBalanceAfter, 0);


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

// TODO:
// - make it so that every time we read or update a user's spot/perp balance, we provide the up-to-date ntl using the current price info
// - experiment with archive node and calling precompiles from older, specific block.number (instead of latest by default)
