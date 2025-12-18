// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {HLConversions} from "../../../src/common/HLConversions.sol";
import {HLConstants} from "../../../src/common/HLConstants.sol";
import {HyperCore} from "../../simulation/HyperCore.sol";
import {CoreSimulatorLib} from "../../simulation/CoreSimulatorLib.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";
import {VaultExample} from "../../../src/examples/VaultExample.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
using Math for uint64;

contract VaultTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    uint64 public constant USDC_TOKEN = 0;
    uint64 public constant HYPE_TOKEN = 150;
    uint32 public constant HYPE_SPOT = 107;

    // Test vault address
    address public constant TEST_VAULT = 0x07Fd993f0fA3A185F7207ADcCD29f7A87404689D;
    address public constant TEST_VAULT_2 = 0xaC26Cf5F3C46B5e102048c65b977d2551B72A9c7;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    function setUp() public {
        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        CoreSimulatorLib.forceAccountActivation(user);
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC VAULT DEPOSIT TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultDeposit() public {
        vm.startPrank(user);

        // Bridge HYPE and sell for USDC
        uint256 initialBalance = 10_000e18;
        uint256 amountToBridge = 10e18;
        uint64 token = HYPE_TOKEN;
        uint64 spot = PrecompileLib.getSpotIndex(HYPE_TOKEN);
        deal(address(user), initialBalance);

        CoreWriterLib.bridgeToCore(token, amountToBridge);
        CoreSimulatorLib.nextBlock();

        // Sell HYPE for USDC
        uint64 spotPx = uint64(PrecompileLib.normalizedSpotPx(uint32(spot)));
        uint64 baseAmt = 10e8; // 10 HYPE
        CoreWriterLib.placeLimitOrder(uint32(spot + 10000), false, 0, baseAmt, true, HLConstants.LIMIT_ORDER_TIF_IOC, 1);
        CoreSimulatorLib.nextBlock();

        uint64 usdcBalance = PrecompileLib.spotBalance(address(user), USDC_TOKEN).total;
        uint64 vaultDepositAmt = HLConversions.weiToPerp(usdcBalance);

        // Transfer to perp and deposit to vault
        CoreWriterLib.transferUsdClass(vaultDepositAmt, true);
        CoreWriterLib.vaultTransfer(TEST_VAULT_2, true, vaultDepositAmt);

        CoreSimulatorLib.nextBlock();

        uint256 vaultBalanceAfter = PrecompileLib.userVaultEquity(address(user), TEST_VAULT_2).equity;
        assertEq(vaultBalanceAfter, vaultDepositAmt, "Vault balance should match deposit amount");
    }

    function testVaultDepositWithContract() public {
        VaultExample vaultExample = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vaultExample));
        CoreSimulatorLib.forcePerpBalance(address(vaultExample), 1000e6);

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vaultExample));
        vaultExample.depositToVault(TEST_VAULT, depositAmount);

        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory initialEquity =
            hyperCore.readUserVaultEquity(address(vaultExample), TEST_VAULT);
        assertEq(initialEquity.equity, depositAmount, "Initial vault equity should match deposit");
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT MULTIPLIER TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultMultiplier() public {
        VaultExample vaultExample = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vaultExample));
        CoreSimulatorLib.forcePerpBalance(address(vaultExample), 1000e6);

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vaultExample));
        vaultExample.depositToVault(TEST_VAULT, depositAmount);

        CoreSimulatorLib.nextBlock();

        // Check initial vault equity
        PrecompileLib.UserVaultEquity memory initialEquity =
            hyperCore.readUserVaultEquity(address(vaultExample), TEST_VAULT);
        assertEq(initialEquity.equity, depositAmount, "Initial vault equity should match deposit");

        // Test 10% profit (1.1x multiplier)
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 1.1e18);
        PrecompileLib.UserVaultEquity memory profitEquity =
            hyperCore.readUserVaultEquity(address(vaultExample), TEST_VAULT);
        assertEq(profitEquity.equity, depositAmount * 11 / 10, "Equity with 10% profit should be 110");
    }

    function testVaultMultiplierVariations() public {
        VaultExample vaultExample = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vaultExample));
        CoreSimulatorLib.forcePerpBalance(address(vaultExample), 1000e6);

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vaultExample));
        vaultExample.depositToVault(TEST_VAULT, depositAmount);

        CoreSimulatorLib.nextBlock();

        // Test 5% profit
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 1.05e18);
        PrecompileLib.UserVaultEquity memory equity5 =
            hyperCore.readUserVaultEquity(address(vaultExample), TEST_VAULT);
        assertEq(equity5.equity, depositAmount * 105 / 100, "Equity with 5% profit should match");

        // Test 20% profit
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 1.2e18);
        PrecompileLib.UserVaultEquity memory equity20 =
            hyperCore.readUserVaultEquity(address(vaultExample), TEST_VAULT);
        assertEq(equity20.equity, depositAmount * 120 / 100, "Equity with 20% profit should match");

        // Test 50% loss
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 0.5e18);
        PrecompileLib.UserVaultEquity memory equityLoss =
            hyperCore.readUserVaultEquity(address(vaultExample), TEST_VAULT);
        assertEq(equityLoss.equity, depositAmount * 50 / 100, "Equity with 50% loss should match");
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultDepositWithdraw() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 100e6);

        uint64 depositAmount = 100e6;

        vm.startPrank(address(vault));

        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        // Try to withdraw before the lock period expires - should revert
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        vm.expectRevert(
            abi.encodeWithSelector(
                CoreWriterLib.CoreWriterLib__StillLockedUntilTimestamp.selector, vaultEquity.lockedUntilTimestamp
            )
        );
        vault.withdrawFromVault(TEST_VAULT, depositAmount);

        // Set multiplier for yield
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 1.1e18);

        // Warp past lock period
        vm.warp((block.timestamp + 1 days + 1));

        // Now withdrawal should work
        vault.withdrawFromVault(TEST_VAULT, depositAmount * 11 / 10);
        CoreSimulatorLib.nextBlock();

        uint256 perpBalanceAfter = PrecompileLib.withdrawable(address(vault));
        assertEq(perpBalanceAfter, depositAmount * 11 / 10, "Should have deposited amount plus 10% yield");
    }

    function testVaultWithdrawAfterLockPeriod() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 200e6);

        uint64 depositAmount = 100e6;

        vm.startPrank(address(vault));

        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        // Warp past lock period (1 day)
        vm.warp(block.timestamp + 1 days + 1);

        // Withdrawal should now work
        vault.withdrawFromVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory vaultEquityAfter = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(vaultEquityAfter.equity, 0, "Vault equity should be 0 after full withdrawal");
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT LOCK PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultLockPeriod() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 100e6);

        uint64 depositAmount = 50e6;

        vm.startPrank(address(vault));

        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);

        // Lock period should be in the future
        assertGt(vaultEquity.lockedUntilTimestamp, block.timestamp * 1000, "Lock timestamp should be in future");

        // Verify isWithdrawable returns false
        bool canWithdraw = vault.isWithdrawable(address(vault), TEST_VAULT);
        assertFalse(canWithdraw, "Should not be withdrawable before lock expires");

        // Warp past lock
        vm.warp(block.timestamp + 1 days + 1);

        // Now should be withdrawable
        canWithdraw = vault.isWithdrawable(address(vault), TEST_VAULT);
        assertTrue(canWithdraw, "Should be withdrawable after lock expires");
    }

    /*//////////////////////////////////////////////////////////////
                        FORCE VAULT EQUITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testForceVaultEquity() public {
        address testUser = makeAddr("vaultUser");
        CoreSimulatorLib.forceAccountActivation(testUser);

        uint64 equityAmount = 500e6;
        uint64 lockedUntil = uint64(block.timestamp * 1000 + 1 days * 1000);

        CoreSimulatorLib.forceVaultEquity(testUser, TEST_VAULT, equityAmount, lockedUntil);

        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(testUser, TEST_VAULT);
        assertEq(vaultEquity.equity, equityAmount, "Forced equity should match");
        assertEq(vaultEquity.lockedUntilTimestamp, lockedUntil, "Lock timestamp should match");
    }

    function testForceVaultEquityUnlocked() public {
        address testUser = makeAddr("vaultUser2");
        CoreSimulatorLib.forceAccountActivation(testUser);

        uint64 equityAmount = 300e6;
        uint64 lockedUntil = uint64(block.timestamp * 1000 - 1); // Already unlocked

        CoreSimulatorLib.forceVaultEquity(testUser, TEST_VAULT, equityAmount, lockedUntil);

        VaultExample vault = new VaultExample();

        bool canWithdraw = vault.isWithdrawable(testUser, TEST_VAULT);
        assertTrue(canWithdraw, "Should be immediately withdrawable with past lock timestamp");
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMultipleVaultDeposits() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 500e6);

        vm.startPrank(address(vault));

        // Deposit to first vault
        vault.depositToVault(TEST_VAULT, 100e6);
        CoreSimulatorLib.nextBlock();

        // Deposit to second vault
        vault.depositToVault(TEST_VAULT_2, 200e6);
        CoreSimulatorLib.nextBlock();

        // Check both vault equities
        PrecompileLib.UserVaultEquity memory equity1 = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        PrecompileLib.UserVaultEquity memory equity2 = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT_2);

        assertEq(equity1.equity, 100e6, "First vault equity should be 100");
        assertEq(equity2.equity, 200e6, "Second vault equity should be 200");
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT WITH TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function testTransferUsdcToPerpAndDepositToVault() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forceSpotBalance(address(vault), USDC_TOKEN, 1000e8); // 1000 USDC in spot

        vm.startPrank(address(vault));

        uint64 coreAmount = 500e8; // 500 USDC
        vault.transferUsdcToPerpAndDepositToVault(TEST_VAULT, coreAmount);

        CoreSimulatorLib.nextBlock();

        uint64 expectedVaultEquity = HLConversions.weiToPerp(coreAmount);
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(vaultEquity.equity, expectedVaultEquity, "Vault equity should match transferred amount");
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT EQUITY INFO TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetVaultEquityFunction() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 200e6);

        vm.startPrank(address(vault));
        vault.depositToVault(TEST_VAULT, 150e6);
        CoreSimulatorLib.nextBlock();

        (uint64 equity, uint64 lockedUntil) = vault.getVaultEquity(address(vault), TEST_VAULT);
        assertEq(equity, 150e6, "getVaultEquity should return correct equity");
        assertGt(lockedUntil, 0, "lockedUntilTimestamp should be set");
    }

    /*//////////////////////////////////////////////////////////////
                        INSUFFICIENT BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultDepositInsufficientBalance() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 50e6); // Only 50 USDC

        vm.startPrank(address(vault));

        // Try to deposit more than available
        vault.depositToVault(TEST_VAULT, 100e6);

        // Expect revert due to insufficient balance
        CoreSimulatorLib.nextBlock(true);

        // Vault equity should be 0 (deposit failed)
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(vaultEquity.equity, 0, "Vault equity should be 0 after failed deposit");
    }

    function testVaultWithdrawMoreThanEquity() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 100e6);

        vm.startPrank(address(vault));

        vault.depositToVault(TEST_VAULT, 50e6);
        CoreSimulatorLib.nextBlock();

        // Warp past lock period
        vm.warp(block.timestamp + 1 days + 1);

        // Try to withdraw more than deposited
        vault.withdrawFromVault(TEST_VAULT, 100e6);

        // Expect revert
        CoreSimulatorLib.nextBlock(true);

        // Vault equity should still be 50 (withdrawal failed)
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(vaultEquity.equity, 50e6, "Vault equity should be unchanged after failed withdrawal");
    }

    /*//////////////////////////////////////////////////////////////
                        EXTREME MULTIPLIER TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultDoubleMultiplier() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 200e6);

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vault));
        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        // 100% profit (2x multiplier)
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 2e18);
        PrecompileLib.UserVaultEquity memory equity = hyperCore.readUserVaultEquity(address(vault), TEST_VAULT);
        assertEq(equity.equity, depositAmount * 2, "Equity should be doubled");
    }

    function testVaultNearZeroMultiplier() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 200e6);

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vault));
        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        // 99% loss (0.01x multiplier)
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 0.01e18);
        PrecompileLib.UserVaultEquity memory equity = hyperCore.readUserVaultEquity(address(vault), TEST_VAULT);
        assertEq(equity.equity, depositAmount / 100, "Equity should be 1% of original");
    }

    /*//////////////////////////////////////////////////////////////
                        SEQUENTIAL OPERATIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testVaultMultipleDepositsAndWithdrawals() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 500e6);

        vm.startPrank(address(vault));

        // First deposit
        vault.depositToVault(TEST_VAULT, 100e6);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory eq1 = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(eq1.equity, 100e6, "First deposit equity");

        // Warp past lock and add more
        vm.warp(block.timestamp + 1 days + 1);

        // Second deposit
        vault.depositToVault(TEST_VAULT, 50e6);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory eq2 = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(eq2.equity, 150e6, "After second deposit");

        // Warp past new lock
        vm.warp(block.timestamp + 1 days + 1);

        // Partial withdrawal
        vault.withdrawFromVault(TEST_VAULT, 75e6);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory eq3 = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(eq3.equity, 75e6, "After partial withdrawal");
    }

    /*//////////////////////////////////////////////////////////////
                        LOCK PERIOD EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testVaultWithdrawExactlyAtLockExpiry() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 100e6);

        uint64 depositAmount = 50e6;
        vm.startPrank(address(vault));

        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        // Warp just past lock expiry (lock is exclusive, so we need to be > lockTime)
        vm.warp(block.timestamp + 1 days + 1);

        // Should be able to withdraw now
        vault.withdrawFromVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(vaultEquity.equity, 0, "Should be able to withdraw past lock expiry");
    }

    /*//////////////////////////////////////////////////////////////
                        ZERO AMOUNT EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function testVaultDepositZeroAmount() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 100e6);

        vm.startPrank(address(vault));

        vault.depositToVault(TEST_VAULT, 0); // Zero deposit
        CoreSimulatorLib.nextBlock();

        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(vault), TEST_VAULT);
        assertEq(vaultEquity.equity, 0, "Zero deposit should result in zero equity");
    }

    /*//////////////////////////////////////////////////////////////
                        PROFIT AND LOSS CYCLES
    //////////////////////////////////////////////////////////////*/

    function testVaultProfitThenLoss() public {
        VaultExample vault = new VaultExample();
        CoreSimulatorLib.forceAccountActivation(address(vault));
        CoreSimulatorLib.forcePerpBalance(address(vault), 200e6);

        uint64 depositAmount = 100e6;
        vm.startPrank(address(vault));
        vault.depositToVault(TEST_VAULT, depositAmount);
        CoreSimulatorLib.nextBlock();

        // First: 20% profit
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 1.2e18);
        PrecompileLib.UserVaultEquity memory eqProfit = hyperCore.readUserVaultEquity(address(vault), TEST_VAULT);
        assertEq(eqProfit.equity, 120e6, "Should have 20% profit");

        // Then: 25% loss from peak (back to below original)
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 0.9e18);
        PrecompileLib.UserVaultEquity memory eqLoss = hyperCore.readUserVaultEquity(address(vault), TEST_VAULT);
        assertEq(eqLoss.equity, 90e6, "Should have 10% net loss");
    }

    /*//////////////////////////////////////////////////////////////
                        MULTIPLE USER VAULT TESTS
    //////////////////////////////////////////////////////////////*/

    function testMultipleUsersInSameVault() public {
        VaultExample vault1 = new VaultExample();
        VaultExample vault2 = new VaultExample();

        CoreSimulatorLib.forceAccountActivation(address(vault1));
        CoreSimulatorLib.forceAccountActivation(address(vault2));
        CoreSimulatorLib.forcePerpBalance(address(vault1), 200e6);
        CoreSimulatorLib.forcePerpBalance(address(vault2), 300e6);

        // User 1 deposits
        vm.startPrank(address(vault1));
        vault1.depositToVault(TEST_VAULT, 100e6);
        CoreSimulatorLib.nextBlock();

        // User 2 deposits
        vm.startPrank(address(vault2));
        vault2.depositToVault(TEST_VAULT, 200e6);
        CoreSimulatorLib.nextBlock();

        // Both should have their deposits
        PrecompileLib.UserVaultEquity memory eq1 = PrecompileLib.userVaultEquity(address(vault1), TEST_VAULT);
        PrecompileLib.UserVaultEquity memory eq2 = PrecompileLib.userVaultEquity(address(vault2), TEST_VAULT);

        assertEq(eq1.equity, 100e6, "User 1 equity should be 100");
        assertEq(eq2.equity, 200e6, "User 2 equity should be 200");

        // Multiplier affects both
        CoreSimulatorLib.setVaultMultiplier(TEST_VAULT, 1.5e18);

        eq1 = PrecompileLib.userVaultEquity(address(vault1), TEST_VAULT);
        eq2 = PrecompileLib.userVaultEquity(address(vault2), TEST_VAULT);

        assertEq(eq1.equity, 150e6, "User 1 equity should grow to 150");
        assertEq(eq2.equity, 300e6, "User 2 equity should grow to 300");
    }
}
