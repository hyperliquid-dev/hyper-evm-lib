// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {HyperCore} from "../simulation/HyperCore.sol";
import {CoreSimulatorLib} from "../simulation/CoreSimulatorLib.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {CoreWriterLib} from "../../src/CoreWriterLib.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";
import {HLConversions} from "../../src/common/HLConversions.sol";

contract FeeSimulationTest is Test {
    HyperCore hyperCore;
    address user = makeAddr("user");

    uint64 constant USDC = 0;
    uint64 constant HYPE = 150;
    uint32 constant HYPE_SPOT = 107;
    uint16 constant HYPE_PERP = 159;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        hyperCore = CoreSimulatorLib.init();

        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceSpotBalance(user, USDC, 10_000e8);
        CoreSimulatorLib.forceSpotBalance(user, HYPE, 0);
        CoreSimulatorLib.forcePerpBalance(user, 10_000e6);
        CoreSimulatorLib.forcePerpLeverage(user, HYPE_PERP, 10);
    }

    function test_spotFee_onBuy() public {
        uint64 baseSz = 10e8; // 10 HYPE (in sz=8 decimals notation)
        uint64 usdcBefore = PrecompileLib.spotBalance(user, USDC).total;
        uint64 hypeBefore = PrecompileLib.spotBalance(user, HYPE).total;
        CoreSimulatorLib.setSpotPx(HYPE_SPOT, PrecompileLib.spotPx(HYPE_SPOT));


        uint32 assetId = HLConversions.spotToAssetId(HYPE_SPOT);
        uint64 limitPx = uint64(PrecompileLib.normalizedSpotPx(HYPE_SPOT));

        vm.startPrank(user);
        CoreWriterLib.placeLimitOrder(assetId, true, limitPx, baseSz, false, HLConstants.LIMIT_ORDER_TIF_IOC, 1);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter = PrecompileLib.spotBalance(user, USDC).total;
        uint64 hypeAfter = PrecompileLib.spotBalance(user, HYPE).total;

        PrecompileLib.TokenInfo memory hypeInfo = PrecompileLib.tokenInfo(HYPE);
        uint64 spotPxRaw = hyperCore.readSpotPx(HYPE_SPOT) * uint64(10 ** hypeInfo.szDecimals);
        uint64 amountIn = uint64((uint256(baseSz) * uint256(spotPxRaw)) / 1e8);
        uint64 fee = uint64(uint256(amountIn) * 400 / 1e6);

        assertEq(usdcBefore - usdcAfter, amountIn + fee, "USDC debit should equal notional plus maker fee");
        assertEq(hypeAfter - hypeBefore, baseSz, "Exact base amount should be received");
    }

    function test_spotFee_onSell() public {
        CoreSimulatorLib.setSpotMakerFee(280);
        CoreSimulatorLib.setSpotPx(HYPE_SPOT, PrecompileLib.spotPx(HYPE_SPOT));

        // Provide inventory for selling
        CoreSimulatorLib.forceSpotBalance(user, HYPE, 20e8);
        CoreSimulatorLib.forceSpotBalance(user, USDC, 0);

        uint64 baseSz = 5e8; // 5 HYPE
        uint64 usdcBefore = PrecompileLib.spotBalance(user, USDC).total;
        uint64 hypeBefore = PrecompileLib.spotBalance(user, HYPE).total;

        uint32 assetId = HLConversions.spotToAssetId(HYPE_SPOT);
        uint64 limitPx = uint64(PrecompileLib.normalizedSpotPx(HYPE_SPOT));

        vm.startPrank(user);
        CoreWriterLib.placeLimitOrder(assetId, false, limitPx, baseSz, false, HLConstants.LIMIT_ORDER_TIF_IOC, 1);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 usdcAfter = PrecompileLib.spotBalance(user, USDC).total;
        uint64 hypeAfter = PrecompileLib.spotBalance(user, HYPE).total;

        PrecompileLib.TokenInfo memory hypeInfo = PrecompileLib.tokenInfo(HYPE);
        uint64 spotPxRaw = hyperCore.readSpotPx(HYPE_SPOT) * uint64(10 ** hypeInfo.szDecimals);
        uint64 amountOut = uint64((uint256(baseSz) * uint256(spotPxRaw)) / 1e8);
        uint64 fee = uint64(uint256(amountOut) * 280 / 1e6);
        uint64 netProceeds = amountOut - fee;

        assertEq(usdcAfter - usdcBefore, netProceeds, "Quote proceeds should net out fee");
        assertEq(hypeBefore - hypeAfter, baseSz, "Base balance should decrease by sell size");
    }

    function test_perpFee_onLong() public {
        uint64 sz = 1e8;
        uint64 perpBalanceBefore = hyperCore.readPerpBalance(user);

        CoreSimulatorLib.setMarkPx(HYPE_PERP, PrecompileLib.markPx(HYPE_PERP));


        uint256 startingPrice = PrecompileLib.markPx(HYPE_PERP);

        vm.startPrank(user);
        CoreWriterLib.placeLimitOrder(HYPE_PERP, true, type(uint64).max, sz, false, HLConstants.LIMIT_ORDER_TIF_IOC, 1);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 perpBalanceAfter = hyperCore.readPerpBalance(user);

        uint64 scaledSz = _scalePerpSz(sz);
        uint256 notional = uint256(scaledSz) * uint256(startingPrice);
        uint64 expectedFee = uint64(notional * 150 / 1e6);

        assertEq(perpBalanceBefore - perpBalanceAfter, expectedFee, "Perp balance should be debited by maker fee");
    }

    function test_perpFee_onShort() public {
        CoreSimulatorLib.setMarkPx(HYPE_PERP, PrecompileLib.markPx(HYPE_PERP));

        uint256 startingPrice = PrecompileLib.markPx(HYPE_PERP);

        uint64 sz = 2e8;
        uint64 perpBalanceBefore = hyperCore.readPerpBalance(user);

        vm.startPrank(user);
        CoreWriterLib.placeLimitOrder(HYPE_PERP, false, 0, sz, false, HLConstants.LIMIT_ORDER_TIF_IOC, 2);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint64 perpBalanceAfter = hyperCore.readPerpBalance(user);

        uint64 scaledSz = _scalePerpSz(sz);
        uint256 notional = uint256(scaledSz) * uint256(startingPrice);
        uint64 expectedFee = uint64(notional * 150 / 1e6);

        assertApproxEqAbs(
            perpBalanceBefore - perpBalanceAfter, expectedFee, 2, "Short orders should also pay maker fees on notional"
        );
    }

    function _scalePerpSz(uint64 amount) internal returns (uint64) {
        uint8 perpSzDecimals = PrecompileLib.perpAssetInfo(HYPE_PERP).szDecimals;
        if (perpSzDecimals == 8) {
            return amount;
        } else if (perpSzDecimals < 8) {
            return amount / (uint64(10) ** (8 - perpSzDecimals));
        } else {
            return amount * (uint64(10) ** (perpSzDecimals - 8));
        }
    }
}
