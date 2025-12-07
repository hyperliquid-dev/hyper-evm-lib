// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {CoreSimulatorLib} from "../simulation/CoreSimulatorLib.sol";

import {CoreWriterLib, HLConversions, HLConstants} from "../../src/CoreWriterLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
contract BridgingTest is Test {
    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        CoreSimulatorLib.init();
    }

    function test_bridgeUSDCToCore() public {
        IERC20 USDC = IERC20(0xb88339CB7199b77E23DB6E890353E22632Ba630f);
        
        address user = makeAddr("user");
        deal(address(USDC), user, 1000e6);
        vm.startPrank(user);
        CoreWriterLib.bridgeToCore(address(USDC), 1000e6);
        vm.stopPrank();

        uint64 activationFee = !PrecompileLib.coreUserExists(user) ? 1e8 : 0;

        CoreSimulatorLib.nextBlock();

        assertEq(PrecompileLib.spotBalance(address(user), 0).total, HLConversions.evmToWei(0, 1000e6) - activationFee);
    }

    // TODO: To be able to bridge to perp dexes directly, SendAsset action needs to be implemented. Requires refactor of CoreState to support multiple perp dexes (HIP-3)
    function test_bridgeUSDCToCoreForRecipient() public {
        IERC20 USDC = IERC20(0xb88339CB7199b77E23DB6E890353E22632Ba630f);
        address recipient = makeAddr("recipient");
        address user = makeAddr("user");
        deal(address(USDC), user, 1000e6);
        vm.startPrank(user);
        CoreWriterLib.bridgeUsdcToCoreFor(recipient, 1000e6, HLConstants.SPOT_DEX);
        vm.stopPrank();

        uint64 activationFee = !PrecompileLib.coreUserExists(recipient) ? 1e8 : 0;

        CoreSimulatorLib.nextBlock();

        assertEq(PrecompileLib.spotBalance(address(recipient), 0).total, HLConversions.evmToWei(0, 1000e6) - activationFee);
    }

    function test_bridgeCoreToEvm() public {
        IERC20 USDC = IERC20(0xb88339CB7199b77E23DB6E890353E22632Ba630f);
        address user = makeAddr("user");
        // Give the user some USDC, then bridge it to Core
        deal(address(USDC), user, 5000e6);
        vm.startPrank(user);
        CoreWriterLib.bridgeToCore(address(USDC), 1000e6);
        vm.stopPrank();

        // Move to next block to process bridge
        CoreSimulatorLib.nextBlock();
        PrecompileLib.SpotBalance memory spotBalance = PrecompileLib.spotBalance(address(user), 0);

        assertEq(spotBalance.total, HLConversions.evmToWei(0, 1000e6) - 1e8);

        // Bridge from Core back to EVM (simulate core withdrawal)
        vm.startPrank(user);
        CoreWriterLib.bridgeToEvm(address(USDC), 500e6);
        vm.stopPrank();

        // Move to next block to process withdrawal
        CoreSimulatorLib.nextBlock();

        // Expect user's EVM USDC balance increased by 500e6
        // (This assumes the CoreSimulatorLib processes withdrawal immediately.)
        assertEq(USDC.balanceOf(user), 4500e6);
    }
}
