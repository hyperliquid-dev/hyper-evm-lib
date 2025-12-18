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
import {RealL1Read} from "../../utils/RealL1Read.sol";

contract BuilderFeeApprover {
    function approveBuilderFee(uint64 maxFeeRate, address builder) public {
        CoreWriterLib.approveBuilderFee(maxFeeRate, builder);
    }
}

contract ApiWalletAdder {
    function addApiWallet(address wallet, string memory name) public {
        CoreWriterLib.addApiWallet(wallet, name);
    }
}

contract OrderCanceller {
    function cancelOrderByOrderId(uint32 asset, uint64 orderId) public {
        CoreWriterLib.cancelOrderByOrderId(asset, orderId);
    }

    function cancelOrderByCloid(uint32 asset, uint128 cloid) public {
        CoreWriterLib.cancelOrderByCloid(asset, cloid);
    }

    function placeLimitOrderGTC(uint32 asset, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint128 cloid) public {
        CoreWriterLib.placeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, HLConstants.LIMIT_ORDER_TIF_GTC, cloid);
    }
}

contract AccountManagementTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;

    uint64 public constant USDC_TOKEN = 0;
    uint64 public constant HYPE_TOKEN = 150;
    uint16 public constant BTC_PERP = 0;
    uint16 public constant HYPE_PERP = 159;
    uint32 public constant HYPE_SPOT = 107;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    function setUp() public {
        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        CoreSimulatorLib.forceAccountActivation(user);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNT ACTIVATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testAccountActivationFee() public {
        vm.startPrank(user);

        // Give sender 10 USDC
        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 10e8);

        address newAccount = makeAddr("newAccount");

        uint64 before = PrecompileLib.spotBalance(user, USDC_TOKEN).total;

        // Send 2 USDC to new account
        CoreWriterLib.spotSend(newAccount, USDC_TOKEN, 2e8);
        CoreSimulatorLib.nextBlock();

        uint64 afterBalance = PrecompileLib.spotBalance(user, USDC_TOKEN).total;

        // Should deduct 3 USDC total (2 transfer + 1 creation fee)
        assertEq(before - afterBalance, 3e8, "Should deduct 2 USDC + 1 USDC creation fee");
    }

    function testAccountActivationFeeOnlyOnce() public {
        vm.startPrank(user);

        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 20e8);

        address newAccount = makeAddr("newAccount2");

        // First transfer - should include activation fee
        uint64 before1 = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        CoreWriterLib.spotSend(newAccount, USDC_TOKEN, 2e8);
        CoreSimulatorLib.nextBlock();
        uint64 after1 = PrecompileLib.spotBalance(user, USDC_TOKEN).total;

        // First transfer includes activation fee
        assertEq(before1 - after1, 3e8, "First transfer should include activation fee");

        // Second transfer - no activation fee
        uint64 before2 = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        CoreWriterLib.spotSend(newAccount, USDC_TOKEN, 2e8);
        CoreSimulatorLib.nextBlock();
        uint64 after2 = PrecompileLib.spotBalance(user, USDC_TOKEN).total;

        // Second transfer no activation fee
        assertEq(before2 - after2, 2e8, "Second transfer should not include activation fee");
    }

    function testNoActivationFeeForExistingAccount() public {
        vm.startPrank(user);

        CoreSimulatorLib.forceSpotBalance(user, USDC_TOKEN, 10e8);

        address existingAccount = makeAddr("existingAccount");
        CoreSimulatorLib.forceAccountActivation(existingAccount);

        uint64 before = PrecompileLib.spotBalance(user, USDC_TOKEN).total;
        CoreWriterLib.spotSend(existingAccount, USDC_TOKEN, 2e8);
        CoreSimulatorLib.nextBlock();
        uint64 afterBalance = PrecompileLib.spotBalance(user, USDC_TOKEN).total;

        // No activation fee for already-activated account
        assertEq(before - afterBalance, 2e8, "Should only deduct transfer amount for existing account");
    }

    /*//////////////////////////////////////////////////////////////
                        BUILDER FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function testApproveBuilderFee() public {
        vm.startPrank(user);
        BuilderFeeApprover approver = new BuilderFeeApprover();
        CoreSimulatorLib.forceAccountActivation(address(approver));

        // Approve various builder fees
        approver.approveBuilderFee(10, user);
        CoreSimulatorLib.nextBlock();

        approver.approveBuilderFee(type(uint64).max, USDT0);
        CoreSimulatorLib.nextBlock();

        address zeroFeeBuilder = makeAddr("zeroFeeBuilder");
        approver.approveBuilderFee(0, zeroFeeBuilder);
        CoreSimulatorLib.nextBlock();

        // All approvals should succeed without revert
    }

    function testApproveBuilderFeeWithDifferentRates() public {
        vm.startPrank(user);
        BuilderFeeApprover approver = new BuilderFeeApprover();
        CoreSimulatorLib.forceAccountActivation(address(approver));

        address builder1 = makeAddr("builder1");
        address builder2 = makeAddr("builder2");
        address builder3 = makeAddr("builder3");

        // Test different fee rates
        approver.approveBuilderFee(100, builder1);   // 1% fee
        approver.approveBuilderFee(500, builder2);   // 5% fee
        approver.approveBuilderFee(1000, builder3);  // 10% fee

        CoreSimulatorLib.nextBlock();

        // All should succeed
    }

    /*//////////////////////////////////////////////////////////////
                        API WALLET TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddApiWallet() public {
        vm.startPrank(user);
        ApiWalletAdder adder = new ApiWalletAdder();
        CoreSimulatorLib.forceAccountActivation(address(adder));

        address apiWallet = makeAddr("apiWallet");

        adder.addApiWallet(apiWallet, "My API Wallet");

        CoreSimulatorLib.nextBlock();

        // API wallet addition should succeed without revert
    }

    function testAddMultipleApiWallets() public {
        vm.startPrank(user);
        ApiWalletAdder adder = new ApiWalletAdder();
        CoreSimulatorLib.forceAccountActivation(address(adder));

        address apiWallet1 = makeAddr("apiWallet1");
        address apiWallet2 = makeAddr("apiWallet2");
        address apiWallet3 = makeAddr("apiWallet3");

        adder.addApiWallet(apiWallet1, "Trading Bot 1");
        adder.addApiWallet(apiWallet2, "Trading Bot 2");
        adder.addApiWallet(apiWallet3, "Analytics");

        CoreSimulatorLib.nextBlock();

        // All API wallet additions should succeed
    }

    /*//////////////////////////////////////////////////////////////
                        ORDER CANCELLATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testCancelOrderByCloid() public {
        vm.startPrank(user);
        OrderCanceller canceller = new OrderCanceller();
        CoreSimulatorLib.forceAccountActivation(address(canceller));
        CoreSimulatorLib.forcePerpBalance(address(canceller), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        uint128 cloid = 12345;

        // Place a GTC order (won't execute immediately if price is far)
        canceller.placeLimitOrderGTC(BTC_PERP, true, startingPrice / 2, 1e8, false, cloid);

        CoreSimulatorLib.nextBlock();

        // Cancel by cloid
        canceller.cancelOrderByCloid(BTC_PERP, cloid);

        CoreSimulatorLib.nextBlock();

        // Order should be cancelled - verify no position was opened
        PrecompileLib.Position memory position = PrecompileLib.position(address(canceller), BTC_PERP);
        assertEq(position.szi, 0, "Position should be 0 after cancellation");
    }

    function testCancelOrderByOrderId() public {
        vm.startPrank(user);
        OrderCanceller canceller = new OrderCanceller();
        CoreSimulatorLib.forceAccountActivation(address(canceller));
        CoreSimulatorLib.forcePerpBalance(address(canceller), 10_000e6);

        uint64 startingPrice = 1000000;
        CoreSimulatorLib.setMarkPx(BTC_PERP, startingPrice);

        // Place a GTC order
        canceller.placeLimitOrderGTC(BTC_PERP, true, startingPrice / 2, 1e8, false, 99999);

        CoreSimulatorLib.nextBlock();

        // Cancel by order ID (using arbitrary order ID for test - in real scenario would get from event)
        canceller.cancelOrderByOrderId(BTC_PERP, 1);

        CoreSimulatorLib.nextBlock();

        // Verify cancellation doesn't cause revert
    }

    function testCancelSpotOrderByCloid() public {
        vm.startPrank(user);
        OrderCanceller canceller = new OrderCanceller();
        CoreSimulatorLib.forceAccountActivation(address(canceller));
        CoreSimulatorLib.forceSpotBalance(address(canceller), USDC_TOKEN, 10000e8);
        CoreSimulatorLib.forceSpotBalance(address(canceller), HYPE_TOKEN, 100e8);

        uint64 currentSpotPx = uint64(PrecompileLib.normalizedSpotPx(HYPE_SPOT));
        uint128 cloid = 54321;

        // Place a GTC sell order above market (won't execute immediately)
        canceller.placeLimitOrderGTC(HYPE_SPOT + 10000, false, currentSpotPx * 2, 10e8, false, cloid);

        CoreSimulatorLib.nextBlock();

        // Cancel by cloid
        canceller.cancelOrderByCloid(HYPE_SPOT + 10000, cloid);

        CoreSimulatorLib.nextBlock();

        // HYPE balance should not have changed (order was cancelled before execution)
    }

    /*//////////////////////////////////////////////////////////////
                        FORCE ACCOUNT ACTIVATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testForceAccountActivation() public {
        address newUser = makeAddr("newUser");

        // Before activation, user shouldn't exist on core
        bool existsBefore = PrecompileLib.coreUserExists(newUser);
        // Note: This may return true if the address has any on-chain activity

        CoreSimulatorLib.forceAccountActivation(newUser);

        // After force activation, user should exist
        bool existsAfter = PrecompileLib.coreUserExists(newUser);
        assertTrue(existsAfter, "User should exist after force activation");
    }

    /*//////////////////////////////////////////////////////////////
                        FORCE BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function testForceSpotBalance() public {
        address testUser = makeAddr("balanceUser");
        CoreSimulatorLib.forceAccountActivation(testUser);

        uint64 balanceAmount = 5000e8;
        CoreSimulatorLib.forceSpotBalance(testUser, USDC_TOKEN, balanceAmount);

        uint64 actualBalance = PrecompileLib.spotBalance(testUser, USDC_TOKEN).total;
        assertEq(actualBalance, balanceAmount, "Forced spot balance should match");
    }

    function testForcePerpBalance() public {
        address testUser = makeAddr("perpUser");
        CoreSimulatorLib.forceAccountActivation(testUser);

        uint64 balanceAmount = 10_000e6;
        CoreSimulatorLib.forcePerpBalance(testUser, balanceAmount);

        uint64 withdrawable = PrecompileLib.withdrawable(testUser);
        assertEq(withdrawable, balanceAmount, "Forced perp balance should match");
    }

    function testForcePerpLeverage() public {
        address testUser = makeAddr("leverageUser");
        CoreSimulatorLib.forceAccountActivation(testUser);
        CoreSimulatorLib.forcePerpBalance(testUser, 10_000e6);

        uint32 leverage = 5;
        CoreSimulatorLib.forcePerpLeverage(testUser, HYPE_PERP, leverage);

        // Leverage is set - would need to open a position to verify
    }

    /*//////////////////////////////////////////////////////////////
                        L1 READ TESTS
    //////////////////////////////////////////////////////////////*/

    function testL1BlockNumber() public {
        // Use RealL1Read to make direct RPC call (PrecompileLib.l1BlockNumber() isn't simulated)
        uint64 blockNumber = RealL1Read.l1BlockNumber();
        assertGt(blockNumber, 0, "L1 block number should be positive");
    }

    function testCoreUserExists() public {
        // Test with a known whale address
        address whale = 0x2Ba553d9F990a3B66b03b2dC0D030dfC1c061036;
        bool exists = PrecompileLib.coreUserExists(whale);
        assertTrue(exists, "Known whale should exist on core");

        // Test with a random address that likely doesn't exist
        address randomAddr = makeAddr("randomNonExistent");
        bool notExists = PrecompileLib.coreUserExists(randomAddr);
        // This may or may not be false depending on simulation state
    }

    /*//////////////////////////////////////////////////////////////
                        SPOT PRICE READ TESTS
    //////////////////////////////////////////////////////////////*/

    function testSpotPrice() public {
        uint64 px = PrecompileLib.spotPx(HYPE_SPOT);
        assertGt(px, 0, "Spot price should be positive");
    }

    function testNormalizedSpotPrice() public {
        uint256 normalizedPx = PrecompileLib.normalizedSpotPx(HYPE_SPOT);
        assertGt(normalizedPx, 0, "Normalized spot price should be positive");
    }

    /*//////////////////////////////////////////////////////////////
                        MARK PRICE READ TESTS
    //////////////////////////////////////////////////////////////*/

    function testMarkPrice() public {
        uint64 px = PrecompileLib.markPx(BTC_PERP);
        assertGt(px, 0, "Mark price should be positive");
    }

    function testNormalizedMarkPrice() public {
        uint256 normalizedPx = PrecompileLib.normalizedMarkPx(BTC_PERP);
        assertGt(normalizedPx, 0, "Normalized mark price should be positive");
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN INFO TESTS
    //////////////////////////////////////////////////////////////*/

    function testTokenInfo() public {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(HYPE_TOKEN);
        assertEq(info.name, "HYPE", "Token name should be HYPE");
        assertGt(info.szDecimals, 0, "szDecimals should be positive");
    }

    function testGetTokenIndex() public {
        uint64 index = PrecompileLib.getTokenIndex(USDT0);
        assertGt(index, 0, "USDT0 token index should be positive");
    }

    function testGetSpotIndex() public {
        uint64 spotIndex = PrecompileLib.getSpotIndex(HYPE_TOKEN);
        assertEq(spotIndex, HYPE_SPOT, "HYPE spot index should be 107");
    }
}
