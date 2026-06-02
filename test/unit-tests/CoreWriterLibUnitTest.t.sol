// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CoreWriterLib} from "../../src/CoreWriterLib.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {ICoreWriter} from "../../src/interfaces/ICoreWriter.sol";

/// @notice Mock-based unit tests covering every `CoreWriterLib` action.
/// @dev For each action: (1) `test_encode*_format` verifies the wire-format bytes
///      (1-byte version 0x01 ++ 3-byte action ID ++ abi-encoded args) match the
///      manually-constructed expectation; (2) `test_*_dispatches` verifies the
///      action helper invokes `coreWriter.sendRawAction(<bytes>)` with the exact
///      encoded payload.
contract CoreWriterLibUnitTest is Test {
    address constant CORE_WRITER_ADDR = 0x3333333333333333333333333333333333333333;

    function setUp() public {
        // Give the CoreWriter address bytecode so EXTCODESIZE > 0. vm.mockCall
        // short-circuits actual execution.
        vm.etch(CORE_WRITER_ADDR, hex"00");
    }

    function _expectDispatch(bytes memory expectedAction) internal {
        bytes memory expectedCall = abi.encodeWithSelector(ICoreWriter.sendRawAction.selector, expectedAction);
        vm.mockCall(CORE_WRITER_ADDR, expectedCall, "");
        vm.expectCall(CORE_WRITER_ADDR, expectedCall);
    }

    /*//////////////////////////////////////////////////////////////
                              limitOrder
    //////////////////////////////////////////////////////////////*/

    function test_encodeLimitOrder_format() public pure {
        uint32 asset = 1;
        bool isBuy = true;
        uint64 limitPx = 100_000_000;
        uint64 sz = 50_000_000;
        bool reduceOnly = false;
        uint8 tif = HLConstants.LIMIT_ORDER_TIF_GTC;
        uint128 cloid = 12_345;

        bytes memory encoded = CoreWriterLib.encodeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, tif, cloid);
        bytes memory expected = abi.encodePacked(
            HLConstants.LIMIT_ORDER_ACTION, abi.encode(asset, isBuy, limitPx, sz, reduceOnly, tif, cloid)
        );

        assertEq(encoded, expected);
        assertEq(uint8(encoded[0]), 1);
        assertEq(uint8(encoded[3]), 0x01);
    }

    function test_encodeLimitOrder_allTifs() public pure {
        uint32 asset = 1;
        uint64 limitPx = 100_000_000;
        uint64 sz = 50_000_000;
        uint128 cloid = 0;

        for (uint8 tif = 1; tif <= 3; tif++) {
            bytes memory encoded = CoreWriterLib.encodeLimitOrder(asset, true, limitPx, sz, false, tif, cloid);
            bytes memory expected = abi.encodePacked(
                HLConstants.LIMIT_ORDER_ACTION, abi.encode(asset, true, limitPx, sz, false, tif, cloid)
            );
            assertEq(encoded, expected);
        }
    }

    function test_placeLimitOrder_dispatches() public {
        uint32 asset = 1;
        bool isBuy = true;
        uint64 limitPx = 100_000_000;
        uint64 sz = 50_000_000;
        bool reduceOnly = false;
        uint8 tif = HLConstants.LIMIT_ORDER_TIF_GTC;
        uint128 cloid = 12_345;

        bytes memory expected = CoreWriterLib.encodeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, tif, cloid);
        _expectDispatch(expected);

        CoreWriterLib.placeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, tif, cloid);
    }

    /*//////////////////////////////////////////////////////////////
                            vaultTransfer
    //////////////////////////////////////////////////////////////*/

    function test_encodeVaultTransfer_format() public pure {
        address vault = address(0x1234);
        bool isDeposit = true;
        uint64 usd = 1_000_000_000;

        bytes memory encoded = CoreWriterLib.encodeVaultTransfer(vault, isDeposit, usd);
        bytes memory expected = abi.encodePacked(HLConstants.VAULT_TRANSFER_ACTION, abi.encode(vault, isDeposit, usd));

        assertEq(encoded, expected);
    }

    function test_vaultTransfer_deposit_dispatches() public {
        address vault = address(0x1234);
        uint64 usd = 1_000_000_000;

        bytes memory expected = CoreWriterLib.encodeVaultTransfer(vault, true, usd);
        _expectDispatch(expected);

        CoreWriterLib.vaultTransfer(vault, true, usd);
    }

    function test_vaultTransfer_withdraw_dispatches_whenUnlocked() public {
        address vault = address(0x1234);
        uint64 usd = 1_000_000_000;

        // vault lock check reads userVaultEquity precompile. Mock it to return an
        // unlocked vault (lockedUntilTimestamp=0) so the helper proceeds.
        PrecompileLib.UserVaultEquity memory equity =
            PrecompileLib.UserVaultEquity({equity: usd, lockedUntilTimestamp: 0});
        vm.mockCall(HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS, abi.encode(address(this), vault), abi.encode(equity));

        bytes memory expected = CoreWriterLib.encodeVaultTransfer(vault, false, usd);
        _expectDispatch(expected);

        CoreWriterLib.vaultTransfer(vault, false, usd);
    }

    function test_vaultTransfer_withdraw_revertsWhenLocked() public {
        address vault = address(0x1234);
        uint64 usd = 1_000_000_000;
        uint64 lockedUntil = uint64(block.timestamp + 1 hours) * 1000;

        PrecompileLib.UserVaultEquity memory equity =
            PrecompileLib.UserVaultEquity({equity: usd, lockedUntilTimestamp: lockedUntil});
        vm.mockCall(HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS, abi.encode(address(this), vault), abi.encode(equity));

        vm.expectRevert(
            abi.encodeWithSelector(CoreWriterLib.CoreWriterLib__StillLockedUntilTimestamp.selector, lockedUntil)
        );
        this.callVaultWithdraw(vault, usd);
    }

    function callVaultWithdraw(address vault, uint64 usd) external {
        CoreWriterLib.vaultTransfer(vault, false, usd);
    }

    /*//////////////////////////////////////////////////////////////
                            tokenDelegate
    //////////////////////////////////////////////////////////////*/

    function test_encodeTokenDelegate_format() public pure {
        address validator = address(0x5678);
        uint64 amount = 1000;
        bool undelegate = false;

        bytes memory encoded = CoreWriterLib.encodeTokenDelegate(validator, amount, undelegate);
        bytes memory expected =
            abi.encodePacked(HLConstants.TOKEN_DELEGATE_ACTION, abi.encode(validator, amount, undelegate));

        assertEq(encoded, expected);
    }

    function test_delegateToken_dispatches() public {
        address validator = address(0x5678);
        uint64 amount = 1000;

        bytes memory expected = CoreWriterLib.encodeTokenDelegate(validator, amount, false);
        _expectDispatch(expected);

        CoreWriterLib.delegateToken(validator, amount, false);
    }

    /*//////////////////////////////////////////////////////////////
                              staking
    //////////////////////////////////////////////////////////////*/

    function test_encodeStakingDeposit_format() public pure {
        uint64 amount = 5000;
        bytes memory encoded = CoreWriterLib.encodeStakingDeposit(amount);
        bytes memory expected = abi.encodePacked(HLConstants.STAKING_DEPOSIT_ACTION, abi.encode(amount));
        assertEq(encoded, expected);
    }

    function test_depositStake_dispatches() public {
        uint64 amount = 5000;
        bytes memory expected = CoreWriterLib.encodeStakingDeposit(amount);
        _expectDispatch(expected);
        CoreWriterLib.depositStake(amount);
    }

    function test_encodeStakingWithdraw_format() public pure {
        uint64 amount = 3000;
        bytes memory encoded = CoreWriterLib.encodeStakingWithdraw(amount);
        bytes memory expected = abi.encodePacked(HLConstants.STAKING_WITHDRAW_ACTION, abi.encode(amount));
        assertEq(encoded, expected);
    }

    function test_withdrawStake_dispatches() public {
        uint64 amount = 3000;
        bytes memory expected = CoreWriterLib.encodeStakingWithdraw(amount);
        _expectDispatch(expected);
        CoreWriterLib.withdrawStake(amount);
    }

    /*//////////////////////////////////////////////////////////////
                              spotSend
    //////////////////////////////////////////////////////////////*/

    function test_encodeSpotSend_format() public pure {
        address to = address(0x9ABC);
        uint64 token = 42;
        uint64 amount = 100_000;

        bytes memory encoded = CoreWriterLib.encodeSpotSend(to, token, amount);
        bytes memory expected = abi.encodePacked(HLConstants.SPOT_SEND_ACTION, abi.encode(to, token, amount));

        assertEq(encoded, expected);
    }

    function test_spotSend_dispatches() public {
        address to = address(0x9ABC);
        uint64 token = 42;
        uint64 amount = 100_000;

        bytes memory expected = CoreWriterLib.encodeSpotSend(to, token, amount);
        _expectDispatch(expected);

        CoreWriterLib.spotSend(to, token, amount);
    }

    function test_spotSend_revertsOnSelfTransfer() public {
        vm.expectRevert(CoreWriterLib.CoreWriterLib__CannotSelfTransfer.selector);
        this.callSpotSend(address(this), 42, 100);
    }

    function callSpotSend(address to, uint64 token, uint64 amount) external {
        CoreWriterLib.spotSend(to, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          usdClassTransfer
    //////////////////////////////////////////////////////////////*/

    function test_encodeUsdClassTransfer_format() public pure {
        uint64 ntl = 2_000_000_000;
        bool toPerp = true;

        bytes memory encoded = CoreWriterLib.encodeUsdClassTransfer(ntl, toPerp);
        bytes memory expected = abi.encodePacked(HLConstants.USD_CLASS_TRANSFER_ACTION, abi.encode(ntl, toPerp));

        assertEq(encoded, expected);
    }

    function test_transferUsdClass_dispatches() public {
        uint64 ntl = 2_000_000_000;
        bool toPerp = true;

        bytes memory expected = CoreWriterLib.encodeUsdClassTransfer(ntl, toPerp);
        _expectDispatch(expected);

        CoreWriterLib.transferUsdClass(ntl, toPerp);
    }

    /*//////////////////////////////////////////////////////////////
                        finalizeEvmContract
    //////////////////////////////////////////////////////////////*/

    function test_encodeFinalizeEvmContract_format() public pure {
        uint64 token = 10;
        uint8 variant = 1;
        uint64 createNonce = 5;

        bytes memory encoded = CoreWriterLib.encodeFinalizeEvmContract(token, variant, createNonce);
        bytes memory expected =
            abi.encodePacked(HLConstants.FINALIZE_EVM_CONTRACT_ACTION, abi.encode(token, variant, createNonce));

        assertEq(encoded, expected);
    }

    function test_encodeFinalizeEvmContract_allVariants() public pure {
        uint64 token = 10;
        uint64 createNonce = 5;

        for (uint8 variant = 1; variant <= 3; variant++) {
            bytes memory encoded = CoreWriterLib.encodeFinalizeEvmContract(token, variant, createNonce);
            bytes memory expected =
                abi.encodePacked(HLConstants.FINALIZE_EVM_CONTRACT_ACTION, abi.encode(token, variant, createNonce));
            assertEq(encoded, expected);
        }
    }

    function test_finalizeEvmContract_dispatches() public {
        uint64 token = 10;
        uint8 variant = 1;
        uint64 createNonce = 5;

        bytes memory expected = CoreWriterLib.encodeFinalizeEvmContract(token, variant, createNonce);
        _expectDispatch(expected);

        CoreWriterLib.finalizeEvmContract(token, variant, createNonce);
    }

    /*//////////////////////////////////////////////////////////////
                            addApiWallet
    //////////////////////////////////////////////////////////////*/

    function test_encodeAddApiWallet_format() public pure {
        address wallet = address(0xDEF0);
        string memory name = "My API Wallet";

        bytes memory encoded = CoreWriterLib.encodeAddApiWallet(wallet, name);
        bytes memory expected = abi.encodePacked(HLConstants.ADD_API_WALLET_ACTION, abi.encode(wallet, name));

        assertEq(encoded, expected);
    }

    function test_encodeAddApiWallet_emptyName() public pure {
        address wallet = address(0xDEF0);
        string memory name = "";

        bytes memory encoded = CoreWriterLib.encodeAddApiWallet(wallet, name);
        bytes memory expected = abi.encodePacked(HLConstants.ADD_API_WALLET_ACTION, abi.encode(wallet, name));

        assertEq(encoded, expected);
    }

    function test_addApiWallet_dispatches() public {
        address wallet = address(0xDEF0);
        string memory name = "My API Wallet";

        bytes memory expected = CoreWriterLib.encodeAddApiWallet(wallet, name);
        _expectDispatch(expected);

        CoreWriterLib.addApiWallet(wallet, name);
    }

    /*//////////////////////////////////////////////////////////////
                          cancelOrderByOid
    //////////////////////////////////////////////////////////////*/

    function test_encodeCancelOrderByOid_format() public pure {
        uint32 asset = 2;
        uint64 oid = 98_765;

        bytes memory encoded = CoreWriterLib.encodeCancelOrderByOid(asset, oid);
        bytes memory expected = abi.encodePacked(HLConstants.CANCEL_ORDER_BY_OID_ACTION, abi.encode(asset, oid));

        assertEq(encoded, expected);
    }

    function test_cancelOrderByOrderId_dispatches() public {
        uint32 asset = 2;
        uint64 oid = 98_765;

        bytes memory expected = CoreWriterLib.encodeCancelOrderByOid(asset, oid);
        _expectDispatch(expected);

        CoreWriterLib.cancelOrderByOrderId(asset, oid);
    }

    /*//////////////////////////////////////////////////////////////
                          cancelOrderByCloid
    //////////////////////////////////////////////////////////////*/

    function test_encodeCancelOrderByCloid_format() public pure {
        uint32 asset = 2;
        uint128 cloid = 123_456_789;

        bytes memory encoded = CoreWriterLib.encodeCancelOrderByCloid(asset, cloid);
        bytes memory expected = abi.encodePacked(HLConstants.CANCEL_ORDER_BY_CLOID_ACTION, abi.encode(asset, cloid));

        assertEq(encoded, expected);
    }

    function test_cancelOrderByCloid_dispatches() public {
        uint32 asset = 2;
        uint128 cloid = 123_456_789;

        bytes memory expected = CoreWriterLib.encodeCancelOrderByCloid(asset, cloid);
        _expectDispatch(expected);

        CoreWriterLib.cancelOrderByCloid(asset, cloid);
    }

    /*//////////////////////////////////////////////////////////////
                        approveBuilderFee
    //////////////////////////////////////////////////////////////*/

    function test_encodeApproveBuilderFee_format() public pure {
        uint64 maxFeeRate = 10;
        address builder = address(0x1111);

        bytes memory encoded = CoreWriterLib.encodeApproveBuilderFee(maxFeeRate, builder);
        bytes memory expected =
            abi.encodePacked(HLConstants.APPROVE_BUILDER_FEE_ACTION, abi.encode(maxFeeRate, builder));

        assertEq(encoded, expected);
    }

    function test_approveBuilderFee_dispatches() public {
        uint64 maxFeeRate = 10;
        address builder = address(0x1111);

        bytes memory expected = CoreWriterLib.encodeApproveBuilderFee(maxFeeRate, builder);
        _expectDispatch(expected);

        CoreWriterLib.approveBuilderFee(maxFeeRate, builder);
    }

    /*//////////////////////////////////////////////////////////////
                              sendAsset
    //////////////////////////////////////////////////////////////*/

    function test_encodeSendAsset_format() public pure {
        address destination = address(0x2222);
        address subAccount = address(0);
        uint32 sourceDex = HLConstants.SPOT_DEX;
        uint32 destDex = HLConstants.SPOT_DEX;
        uint64 token = 7;
        uint64 amount = 500_000;

        bytes memory encoded = CoreWriterLib.encodeSendAsset(destination, subAccount, sourceDex, destDex, token, amount);
        bytes memory expected = abi.encodePacked(
            HLConstants.SEND_ASSET_ACTION, abi.encode(destination, subAccount, sourceDex, destDex, token, amount)
        );

        assertEq(encoded, expected);
    }

    function test_encodeSendAsset_withSubAccount() public pure {
        address destination = address(0x2222);
        address subAccount = address(0x3333);
        uint32 sourceDex = 1;
        uint32 destDex = 2;
        uint64 token = 7;
        uint64 amount = 500_000;

        bytes memory encoded = CoreWriterLib.encodeSendAsset(destination, subAccount, sourceDex, destDex, token, amount);
        bytes memory expected = abi.encodePacked(
            HLConstants.SEND_ASSET_ACTION, abi.encode(destination, subAccount, sourceDex, destDex, token, amount)
        );

        assertEq(encoded, expected);
    }

    function test_sendAsset_dispatches() public {
        address destination = address(0x2222);
        address subAccount = address(0);
        uint32 sourceDex = HLConstants.SPOT_DEX;
        uint32 destDex = HLConstants.SPOT_DEX;
        uint64 token = 7;
        uint64 amount = 500_000;

        bytes memory expected =
            CoreWriterLib.encodeSendAsset(destination, subAccount, sourceDex, destDex, token, amount);
        _expectDispatch(expected);

        CoreWriterLib.sendAsset(destination, subAccount, sourceDex, destDex, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                      reflectEvmSupplyChange
    //////////////////////////////////////////////////////////////*/

    function test_encodeReflectEvmSupplyChange_format() public pure {
        uint64 token = 15;
        uint64 amount = 1_000_000;
        bool isMint = true;

        bytes memory encoded = CoreWriterLib.encodeReflectEvmSupplyChange(token, amount, isMint);
        bytes memory expected =
            abi.encodePacked(HLConstants.REFLECT_EVM_SUPPLY_CHANGE_ACTION, abi.encode(token, amount, isMint));

        assertEq(encoded, expected);
        // Action ID byte 3 must be 0x0e (14).
        assertEq(uint8(encoded[3]), 0x0e);
    }

    function test_reflectEvmSupplyChange_dispatches() public {
        uint64 token = 15;
        uint64 amount = 1_000_000;
        bool isMint = true;

        bytes memory expected = CoreWriterLib.encodeReflectEvmSupplyChange(token, amount, isMint);
        _expectDispatch(expected);

        CoreWriterLib.reflectEvmSupplyChange(token, amount, isMint);
    }

    /*//////////////////////////////////////////////////////////////
                              borrowLend
    //////////////////////////////////////////////////////////////*/

    function test_encodeBorrowLend_format() public pure {
        uint8 op = HLConstants.BLP_SUPPLY;
        uint64 token = 20;
        uint64 amount = 10_000;

        bytes memory encoded = CoreWriterLib.encodeBorrowLend(op, token, amount);
        bytes memory expected =
            abi.encodePacked(HLConstants.BORROW_LEND_OPERATION_ACTION, abi.encode(op, token, amount));

        assertEq(encoded, expected);
    }

    function test_encodeBorrowLend_allOperations() public pure {
        uint64 token = 20;
        uint64 amount = 10_000;

        bytes memory supply = CoreWriterLib.encodeBorrowLend(HLConstants.BLP_SUPPLY, token, amount);
        bytes memory expectedSupply = abi.encodePacked(
            HLConstants.BORROW_LEND_OPERATION_ACTION, abi.encode(HLConstants.BLP_SUPPLY, token, amount)
        );
        assertEq(supply, expectedSupply);

        bytes memory withdraw = CoreWriterLib.encodeBorrowLend(HLConstants.BLP_WITHDRAW, token, amount);
        bytes memory expectedWithdraw = abi.encodePacked(
            HLConstants.BORROW_LEND_OPERATION_ACTION, abi.encode(HLConstants.BLP_WITHDRAW, token, amount)
        );
        assertEq(withdraw, expectedWithdraw);
    }

    function test_encodeBorrowLend_maxAmountSentinel() public pure {
        // amount=0 applies the operation maximally per HLConstants.BLP_WITHDRAW semantics.
        bytes memory encoded = CoreWriterLib.encodeBorrowLend(HLConstants.BLP_WITHDRAW, 20, 0);
        bytes memory expected = abi.encodePacked(
            HLConstants.BORROW_LEND_OPERATION_ACTION, abi.encode(HLConstants.BLP_WITHDRAW, uint64(20), uint64(0))
        );
        assertEq(encoded, expected);
    }

    function test_borrowLend_dispatches() public {
        uint8 op = HLConstants.BLP_SUPPLY;
        uint64 token = 20;
        uint64 amount = 10_000;

        bytes memory expected = CoreWriterLib.encodeBorrowLend(op, token, amount);
        _expectDispatch(expected);

        CoreWriterLib.borrowLend(op, token, amount);
    }

    /*//////////////////////////////////////////////////////////////
                          format invariants
    //////////////////////////////////////////////////////////////*/

    function test_actionEncoding_versionByte() public pure {
        // Every action selector must begin with 0x01 (CoreWriter wire format version).
        bytes4[15] memory actions = [
            HLConstants.LIMIT_ORDER_ACTION,
            HLConstants.VAULT_TRANSFER_ACTION,
            HLConstants.TOKEN_DELEGATE_ACTION,
            HLConstants.STAKING_DEPOSIT_ACTION,
            HLConstants.STAKING_WITHDRAW_ACTION,
            HLConstants.SPOT_SEND_ACTION,
            HLConstants.USD_CLASS_TRANSFER_ACTION,
            HLConstants.FINALIZE_EVM_CONTRACT_ACTION,
            HLConstants.ADD_API_WALLET_ACTION,
            HLConstants.CANCEL_ORDER_BY_OID_ACTION,
            HLConstants.CANCEL_ORDER_BY_CLOID_ACTION,
            HLConstants.APPROVE_BUILDER_FEE_ACTION,
            HLConstants.SEND_ASSET_ACTION,
            HLConstants.REFLECT_EVM_SUPPLY_CHANGE_ACTION,
            HLConstants.BORROW_LEND_OPERATION_ACTION
        ];
        for (uint256 i = 0; i < actions.length; i++) {
            assertEq(uint8(actions[i][0]), 0x01);
        }
    }

    function test_constants_dexSentinels() public pure {
        assertEq(HLConstants.SPOT_DEX, type(uint32).max);
        assertEq(HLConstants.DEFAULT_PERP_DEX, 0);
    }

    function test_constants_borrowLendOps() public pure {
        assertEq(HLConstants.BLP_SUPPLY, 0);
        assertEq(HLConstants.BLP_WITHDRAW, 1);
    }

    function test_constants_tifValues() public pure {
        assertEq(HLConstants.LIMIT_ORDER_TIF_ALO, 1);
        assertEq(HLConstants.LIMIT_ORDER_TIF_GTC, 2);
        assertEq(HLConstants.LIMIT_ORDER_TIF_IOC, 3);
    }
}
