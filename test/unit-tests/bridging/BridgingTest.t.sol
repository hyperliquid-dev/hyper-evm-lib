// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {HLConversions} from "../../../src/common/HLConversions.sol";
import {HLConstants} from "../../../src/common/HLConstants.sol";
import {BridgingExample} from "../../../src/examples/BridgingExample.sol";
import {HyperCore} from "../../simulation/HyperCore.sol";
import {L1Read} from "../../utils/L1Read.sol";
import {CoreSimulatorLib} from "../../simulation/CoreSimulatorLib.sol";
import {RealL1Read} from "../../utils/RealL1Read.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract BridgingTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    // Token addresses
    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant uBTC = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463;
    address public constant uETH = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;
    address public constant uSOL = 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29;
    address public constant USDC_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

    // Token indices
    uint64 public constant USDC_TOKEN = 0;
    uint64 public constant HYPE_TOKEN = 150;

    HyperCore public hyperCore;
    address public user = makeAddr("user");
    BridgingExample public bridgingExample;
    L1Read l1Read;

    function setUp() public {
        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();
        bridgingExample = new BridgingExample();

        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(address(bridgingExample));

        l1Read = new L1Read();
    }

    /*//////////////////////////////////////////////////////////////
                            HYPE BRIDGING TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeHypeToCore() public {
        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreById{value: 1e18}(HYPE_TOKEN, 1e18);

        (uint64 total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), HYPE_TOKEN)), (uint64, uint64, uint64));
        assertEq(total, 0, "Balance should be 0 before nextBlock");

        CoreSimulatorLib.nextBlock();

        (total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), HYPE_TOKEN)), (uint64, uint64, uint64));
        assertEq(total, HLConversions.evmToWei(HYPE_TOKEN, 1e18), "Balance should match bridged amount");
    }

    function testBridgeToCoreAndSend() public {
        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreAndSendHype{value: 1e18}(1e18, address(user));

        (uint64 total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(user), HYPE_TOKEN)), (uint64, uint64, uint64));
        assertEq(total, 0, "Balance should be 0 before nextBlock");

        CoreSimulatorLib.nextBlock();

        (total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(user), HYPE_TOKEN)), (uint64, uint64, uint64));
        assertEq(total, HLConversions.evmToWei(HYPE_TOKEN, 1e18), "Balance should match bridged amount");
    }

    function testBridgeToCoreAndSendToExistingUser() public {
        address recipient = 0x68e7E72938db36a5CBbCa7b52c71DBBaaDfB8264;

        deal(address(user), 10000e18);

        uint256 amountToSend = 1e18;

        vm.startPrank(user);
        bridgingExample.bridgeToCoreAndSendHype{value: amountToSend}(amountToSend, address(recipient));

        (uint64 realTotal,,) =
            abi.decode(abi.encode(RealL1Read.spotBalance(address(recipient), HYPE_TOKEN)), (uint64, uint64, uint64));

        CoreSimulatorLib.nextBlock();

        (uint64 newTotal,,) =
            abi.decode(abi.encode(l1Read.spotBalance(address(recipient), HYPE_TOKEN)), (uint64, uint64, uint64));
        assertEq(newTotal, realTotal + HLConversions.evmToWei(HYPE_TOKEN, amountToSend), "Balance should include existing + bridged");
    }

    function testBridgeHypeToCoreAndSell() public {
        vm.startPrank(user);

        uint256 initialBalance = 10_000e18;
        uint256 amountToBridge = 10e18;
        uint64 token = HYPE_TOKEN;
        uint64 spot = PrecompileLib.getSpotIndex(HYPE_TOKEN);
        deal(address(user), initialBalance);

        assertEq(address(user).balance, initialBalance);

        CoreWriterLib.bridgeToCore(token, amountToBridge);

        assertEq(address(user).balance, initialBalance - amountToBridge);
        assertEq(PrecompileLib.spotBalance(address(user), token).total, 0);

        CoreSimulatorLib.nextBlock();

        assertEq(address(user).balance, initialBalance - amountToBridge);
        assertEq(PrecompileLib.spotBalance(address(user), token).total, HLConversions.evmToWei(token, amountToBridge));

        // sell to USDC
        uint64 spotPx = uint64(PrecompileLib.normalizedSpotPx(uint32(spot)));

        uint256 usdcBalanceBefore = PrecompileLib.spotBalance(address(user), USDC_TOKEN).total;

        uint64 baseAmt = 10e8; // 10 HYPE
        CoreWriterLib.placeLimitOrder(uint32(spot + 10000), false, 0, baseAmt, true, HLConstants.LIMIT_ORDER_TIF_IOC, 1);

        CoreSimulatorLib.nextBlock();

        uint256 usdcBalanceAfter = PrecompileLib.spotBalance(address(user), USDC_TOKEN).total;
        uint256 hypeBalanceAfter = PrecompileLib.spotBalance(address(user), token).total;

        assertApproxEqAbs(
            usdcBalanceAfter - usdcBalanceBefore,
            uint256(baseAmt) * uint256(spotPx) / 1e8,
            (usdcBalanceAfter - usdcBalanceBefore) * 5 / 1000,
            "USDC received should approximately match expected"
        );
        assertEq(hypeBalanceAfter, 0, "HYPE balance should be 0 after selling all");
    }

    /*//////////////////////////////////////////////////////////////
                            ETH BRIDGING TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeEthToCore() public {
        uint64 uETH_TOKEN = 221;
        deal(address(uETH), address(bridgingExample), 1e18);

        bridgingExample.bridgeToCoreById(uETH_TOKEN, 1e18);

        (uint64 total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), uETH_TOKEN)), (uint64, uint64, uint64));
        assertEq(total, 0, "Balance should be 0 before nextBlock");

        CoreSimulatorLib.nextBlock();

        (total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), uETH_TOKEN)), (uint64, uint64, uint64));
        assertGt(total, 0, "Balance should be > 0 after bridging");
    }

    /*//////////////////////////////////////////////////////////////
                            USDC BRIDGING TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeUSDCToCore() public {
        IERC20 USDC = IERC20(USDC_ADDRESS);

        address testUser = makeAddr("usdcUser");
        deal(address(USDC), testUser, 1000e6);
        vm.startPrank(testUser);
        CoreWriterLib.bridgeToCore(address(USDC), 1000e6);
        vm.stopPrank();

        uint64 activationFee = !PrecompileLib.coreUserExists(testUser) ? 1e8 : 0;

        CoreSimulatorLib.nextBlock();

        assertEq(
            PrecompileLib.spotBalance(address(testUser), USDC_TOKEN).total,
            HLConversions.evmToWei(USDC_TOKEN, 1000e6) - activationFee,
            "USDC balance should match bridged amount minus activation fee"
        );
    }

    function testBridgeUSDCToCoreForRecipient() public {
        IERC20 USDC = IERC20(USDC_ADDRESS);
        address recipient = makeAddr("recipient");
        address sender = makeAddr("sender");
        deal(address(USDC), sender, 1000e6);
        vm.startPrank(sender);
        CoreWriterLib.bridgeUsdcToCoreFor(recipient, 1000e6, HLConstants.SPOT_DEX);
        vm.stopPrank();

        uint64 activationFee = !PrecompileLib.coreUserExists(recipient) ? 1e8 : 0;

        CoreSimulatorLib.nextBlock();

        assertEq(
            PrecompileLib.spotBalance(address(recipient), USDC_TOKEN).total,
            HLConversions.evmToWei(USDC_TOKEN, 1000e6) - activationFee,
            "Recipient USDC balance should match bridged amount minus activation fee"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE TO EVM TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeToEvm() public {
        uint64 uETH_TOKEN = PrecompileLib.getTokenIndex(uETH);

        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(user), uETH_TOKEN, 1e15);

        vm.startPrank(address(user));
        uint256 amount = 20e18;

        CoreWriterLib.bridgeToEvm(uETH, amount);

        CoreSimulatorLib.nextBlock();

        uint256 userBalance = IERC20(uETH).balanceOf(address(user));
        assertEq(userBalance, amount, "EVM balance should match withdrawn amount");
    }

    function testBridgeCoreToEvm() public {
        IERC20 USDC = IERC20(USDC_ADDRESS);
        address testUser = makeAddr("bridgeUser");

        deal(address(USDC), testUser, 5000e6);
        vm.startPrank(testUser);
        CoreWriterLib.bridgeToCore(address(USDC), 1000e6);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();
        PrecompileLib.SpotBalance memory spotBalance = PrecompileLib.spotBalance(address(testUser), USDC_TOKEN);

        assertEq(spotBalance.total, HLConversions.evmToWei(USDC_TOKEN, 1000e6) - 1e8, "Spot balance should match bridged amount minus fee");

        vm.startPrank(testUser);
        CoreWriterLib.bridgeToEvm(address(USDC), 500e6);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        assertEq(USDC.balanceOf(testUser), 4500e6, "EVM USDC balance should be 4500");
    }

    /*//////////////////////////////////////////////////////////////
                            uBTC BRIDGING TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeUBTCToCore() public {
        uint64 uBTC_TOKEN = PrecompileLib.getTokenIndex(uBTC);

        deal(uBTC, address(bridgingExample), 1e8); // 1 BTC

        bridgingExample.bridgeToCoreById(uBTC_TOKEN, 1e8);

        CoreSimulatorLib.nextBlock();

        (uint64 total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), uBTC_TOKEN)), (uint64, uint64, uint64));
        assertGt(total, 0, "uBTC balance should be > 0 after bridging");
    }

    function testBridgeUBTCToEvm() public {
        uint64 uBTC_TOKEN = PrecompileLib.getTokenIndex(uBTC);

        // Deal uBTC to bridgingExample and bridge to core
        deal(uBTC, address(bridgingExample), 10e8); // 10 BTC on EVM

        bridgingExample.bridgeToCoreById(uBTC_TOKEN, 5e8); // bridge 5 BTC to core

        CoreSimulatorLib.nextBlock();

        // Verify the bridgingExample has balance on core
        (uint64 coreBalance,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), uBTC_TOKEN)), (uint64, uint64, uint64));
        assertGt(coreBalance, 0, "Should have uBTC balance on core after bridging");

        // Now bridge back to EVM using bridgingExample
        uint256 evmBalanceBefore = IERC20(uBTC).balanceOf(address(bridgingExample));

        bridgingExample.bridgeToEvmById(uBTC_TOKEN, 1e8); // bridge 1 BTC back to EVM

        CoreSimulatorLib.nextBlock();

        uint256 evmBalanceAfter = IERC20(uBTC).balanceOf(address(bridgingExample));
        assertGt(evmBalanceAfter, evmBalanceBefore, "EVM uBTC balance should increase");
    }

    /*//////////////////////////////////////////////////////////////
                            uSOL BRIDGING TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeUSOLToCore() public {
        uint64 uSOL_TOKEN = PrecompileLib.getTokenIndex(uSOL);

        deal(uSOL, address(bridgingExample), 10e9); // 10 SOL

        bridgingExample.bridgeToCoreById(uSOL_TOKEN, 10e9);

        CoreSimulatorLib.nextBlock();

        (uint64 total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), uSOL_TOKEN)), (uint64, uint64, uint64));
        assertGt(total, 0, "uSOL balance should be > 0 after bridging");
    }

    function testBridgeUSOLToEvm() public {
        uint64 uSOL_TOKEN = PrecompileLib.getTokenIndex(uSOL);

        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(user), uSOL_TOKEN, 10e8); // 10 SOL in core wei

        uint256 evmBalanceBefore = IERC20(uSOL).balanceOf(address(user));

        vm.startPrank(address(user));
        CoreWriterLib.bridgeToEvm(uSOL, 10e9);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint256 evmBalanceAfter = IERC20(uSOL).balanceOf(address(user));
        assertGt(evmBalanceAfter, evmBalanceBefore, "EVM uSOL balance should increase");
    }

    /*//////////////////////////////////////////////////////////////
                            USDT0 BRIDGING TESTS
    //////////////////////////////////////////////////////////////*/

    function testBridgeUSDT0ToCore() public {
        uint64 USDT0_TOKEN = PrecompileLib.getTokenIndex(USDT0);

        deal(USDT0, address(bridgingExample), 1000e6); // 1000 USDT0

        bridgingExample.bridgeToCoreById(USDT0_TOKEN, 1000e6);

        CoreSimulatorLib.nextBlock();

        (uint64 total,,) =
            abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), USDT0_TOKEN)), (uint64, uint64, uint64));
        assertGt(total, 0, "USDT0 balance should be > 0 after bridging");
    }

    function testBridgeUSDT0ToEvm() public {
        uint64 USDT0_TOKEN = PrecompileLib.getTokenIndex(USDT0);

        CoreSimulatorLib.forceAccountActivation(address(user));
        CoreSimulatorLib.forceSpotBalance(address(user), USDT0_TOKEN, 1000e8); // 1000 USDT0 in core wei

        uint256 evmBalanceBefore = IERC20(USDT0).balanceOf(address(user));

        vm.startPrank(address(user));
        CoreWriterLib.bridgeToEvm(USDT0, 500e6);
        vm.stopPrank();

        CoreSimulatorLib.nextBlock();

        uint256 evmBalanceAfter = IERC20(USDT0).balanceOf(address(user));
        assertGt(evmBalanceAfter, evmBalanceBefore, "EVM USDT0 balance should increase");
    }
}
