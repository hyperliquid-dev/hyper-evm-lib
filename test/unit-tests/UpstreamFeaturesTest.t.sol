// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {CoreWriterLib} from "../../src/CoreWriterLib.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";

/**
 * @title UpstreamFeaturesTest
 * @notice Tests for features upstreamed from native-markets/hyperevm-tools:
 *  - `try*` non-reverting precompile variants
 *  - Per-precompile gas caps
 *  - `encode*` CoreWriter action variants
 *  - `reflectEvmSupplyChange` CoreWriter action
 *  - `positionLegacy` (POSITION 0x800 precompile)
 */
contract UpstreamFeaturesTest is Test {
    // Bytecode for `REVERT(0,0)`: PUSH1 00 PUSH1 00 REVERT. Etched at every precompile
    // address so staticcalls fail (success=false) instead of triggering foundry's
    // "call to non-contract address" guard.
    bytes constant REVERTER = hex"60006000fd";

    function setUp() public {
        vm.etch(HLConstants.POSITION_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.SPOT_BALANCE_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.WITHDRAWABLE_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.MARK_PX_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.ORACLE_PX_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.SPOT_PX_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.BBO_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.BORROW_LEND_USER_STATE_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.BORROW_LEND_RESERVE_STATE_PRECOMPILE_ADDRESS, REVERTER);
        vm.etch(HLConstants.POSITION2_PRECOMPILE_ADDRESS, REVERTER);
    }

    /*//////////////////////////////////////////////////////////////
                        try* variants — failure path
        Precompiles etched to revert, so staticcalls return
        success=false; try* must surface that instead of reverting.
    //////////////////////////////////////////////////////////////*/

    function test_tryPosition2_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPosition2(address(0xBEEF), 0);
        assertFalse(success);
        assertEq(result.szi, 0);
        assertEq(result.entryNtl, 0);
    }

    function test_tryPositionLegacy_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPositionLegacy(address(0xBEEF), 0);
        assertFalse(success);
        assertEq(result.szi, 0);
    }

    function test_trySpotBalance_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.SpotBalance memory result, bool success) = PrecompileLib.trySpotBalance(address(0xBEEF), 0);
        assertFalse(success);
        assertEq(result.total, 0);
    }

    function test_tryUserVaultEquity_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.UserVaultEquity memory result, bool success) =
            PrecompileLib.tryUserVaultEquity(address(0xBEEF), address(0xDEAD));
        assertFalse(success);
        assertEq(result.equity, 0);
    }

    function test_tryWithdrawable_returnsFalse_whenPrecompileMissing() public view {
        (uint64 result, bool success) = PrecompileLib.tryWithdrawable(address(0xBEEF));
        assertFalse(success);
        assertEq(result, 0);
    }

    function test_tryDelegations_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.Delegation[] memory result, bool success) = PrecompileLib.tryDelegations(address(0xBEEF));
        assertFalse(success);
        assertEq(result.length, 0);
    }

    function test_tryDelegatorSummary_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.DelegatorSummary memory result, bool success) =
            PrecompileLib.tryDelegatorSummary(address(0xBEEF));
        assertFalse(success);
        assertEq(result.delegated, 0);
    }

    function test_tryMarkPx_returnsFalse_whenPrecompileMissing() public view {
        (uint64 result, bool success) = PrecompileLib.tryMarkPx(0);
        assertFalse(success);
        assertEq(result, 0);
    }

    function test_tryOraclePx_returnsFalse_whenPrecompileMissing() public view {
        (uint64 result, bool success) = PrecompileLib.tryOraclePx(0);
        assertFalse(success);
        assertEq(result, 0);
    }

    function test_trySpotPx_returnsFalse_whenPrecompileMissing() public view {
        (uint64 result, bool success) = PrecompileLib.trySpotPx(0);
        assertFalse(success);
        assertEq(result, 0);
    }

    function test_tryL1BlockNumber_returnsFalse_whenPrecompileMissing() public view {
        (uint64 result, bool success) = PrecompileLib.tryL1BlockNumber();
        assertFalse(success);
        assertEq(result, 0);
    }

    function test_tryBbo_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.Bbo memory result, bool success) = PrecompileLib.tryBbo(0);
        assertFalse(success);
        assertEq(result.bid, 0);
        assertEq(result.ask, 0);
    }

    function test_tryAccountMarginSummary_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.AccountMarginSummary memory result, bool success) =
            PrecompileLib.tryAccountMarginSummary(0, address(0xBEEF));
        assertFalse(success);
        assertEq(result.accountValue, 0);
    }

    function test_tryCoreUserExists_returnsFalse_whenPrecompileMissing() public view {
        (bool exists, bool success) = PrecompileLib.tryCoreUserExists(address(0xBEEF));
        assertFalse(success);
        assertFalse(exists);
    }

    function test_tryBorrowLendUserState_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.BorrowLendUserTokenState memory result, bool success) =
            PrecompileLib.tryBorrowLendUserState(address(0xBEEF), 0);
        assertFalse(success);
        assertEq(result.borrow.basis, 0);
    }

    function test_tryBorrowLendReserveState_returnsFalse_whenPrecompileMissing() public view {
        (PrecompileLib.BorrowLendReserveState memory result, bool success) = PrecompileLib.tryBorrowLendReserveState(0);
        assertFalse(success);
        assertEq(result.balance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                Reverting variants — failure path
    //////////////////////////////////////////////////////////////*/

    function test_position2_reverts_whenPrecompileMissing() public {
        vm.expectRevert();
        this.callPosition2();
    }

    function test_positionLegacy_reverts_whenPrecompileMissing() public {
        vm.expectRevert();
        this.callPositionLegacy();
    }

    function callPosition2() external view {
        PrecompileLib.position2(address(0xBEEF), 0);
    }

    function callPositionLegacy() external view {
        PrecompileLib.positionLegacy(address(0xBEEF), 0);
    }

    /*//////////////////////////////////////////////////////////////
                  encode* variants — byte-level correctness
    //////////////////////////////////////////////////////////////*/

    function test_encodeLimitOrder_format() public pure {
        bytes memory encoded =
            CoreWriterLib.encodeLimitOrder(0, true, 100, 5, false, HLConstants.LIMIT_ORDER_TIF_GTC, 0);
        bytes memory expected = abi.encodePacked(
            HLConstants.LIMIT_ORDER_ACTION,
            abi.encode(uint32(0), true, uint64(100), uint64(5), false, HLConstants.LIMIT_ORDER_TIF_GTC, uint128(0))
        );
        assertEq(encoded, expected);
        assertEq(uint8(encoded[0]), 1);
    }

    function test_encodeSpotSend_format() public pure {
        bytes memory encoded = CoreWriterLib.encodeSpotSend(address(0x1234), 150, 1e8);
        bytes memory expected =
            abi.encodePacked(HLConstants.SPOT_SEND_ACTION, abi.encode(address(0x1234), uint64(150), uint64(1e8)));
        assertEq(encoded, expected);
    }

    function test_encodeStakingDeposit_format() public pure {
        bytes memory encoded = CoreWriterLib.encodeStakingDeposit(1e8);
        bytes memory expected = abi.encodePacked(HLConstants.STAKING_DEPOSIT_ACTION, abi.encode(uint64(1e8)));
        assertEq(encoded, expected);
    }

    function test_encodeReflectEvmSupplyChange_format() public pure {
        bytes memory encoded = CoreWriterLib.encodeReflectEvmSupplyChange(150, 1e8, true);
        bytes memory expected =
            abi.encodePacked(HLConstants.REFLECT_EVM_SUPPLY_CHANGE_ACTION, abi.encode(uint64(150), uint64(1e8), true));
        assertEq(encoded, expected);
        // Action ID byte 3 must be 0x0e (14)
        assertEq(uint8(encoded[3]), 0x0e);
    }

    function test_encodeSendAsset_format() public pure {
        bytes memory encoded = CoreWriterLib.encodeSendAsset(
            address(0x1234), address(0), HLConstants.SPOT_DEX, HLConstants.SPOT_DEX, 150, 1e8
        );
        bytes memory expected = abi.encodePacked(
            HLConstants.SEND_ASSET_ACTION,
            abi.encode(
                address(0x1234), address(0), HLConstants.SPOT_DEX, HLConstants.SPOT_DEX, uint64(150), uint64(1e8)
            )
        );
        assertEq(encoded, expected);
    }

    function test_encodeBorrowLend_format() public pure {
        bytes memory encoded = CoreWriterLib.encodeBorrowLend(HLConstants.BLP_SUPPLY, 150, 1e8);
        bytes memory expected = abi.encodePacked(
            HLConstants.BORROW_LEND_OPERATION_ACTION, abi.encode(HLConstants.BLP_SUPPLY, uint64(150), uint64(1e8))
        );
        assertEq(encoded, expected);
    }

    /*//////////////////////////////////////////////////////////////
                  reflectEvmSupplyChange — sends action
    //////////////////////////////////////////////////////////////*/

    function test_reflectEvmSupplyChange_emitsRawAction() public {
        bytes memory expected = CoreWriterLib.encodeReflectEvmSupplyChange(150, 1e8, true);

        // Stub the CoreWriter system contract: we only need sendRawAction(bytes) to be callable
        // without reverting. A plain empty contract would lack the selector; etch a stub that
        // accepts any call.
        vm.etch(address(CoreWriterLib.coreWriter), hex"00");

        // mockCall returns success on any call data; verify the encoded bytes match what we expect.
        vm.mockCall(
            address(CoreWriterLib.coreWriter),
            abi.encodeWithSelector(bytes4(keccak256("sendRawAction(bytes)")), expected),
            ""
        );
        vm.expectCall(
            address(CoreWriterLib.coreWriter),
            abi.encodeWithSelector(bytes4(keccak256("sendRawAction(bytes)")), expected)
        );
        CoreWriterLib.reflectEvmSupplyChange(150, 1e8, true);
    }

    /*//////////////////////////////////////////////////////////////
                  Gas caps — fixed-size precompiles bounded
    //////////////////////////////////////////////////////////////*/

    function test_gasCap_position_isBounded() public {
        // Without etching the precompile, the call reverts and consumes the forwarded gas only.
        // Measure that the call frame does not consume an unbounded amount.
        uint256 gasBefore = gasleft();
        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPosition2(address(0xBEEF), 0);
        uint256 gasUsed = gasBefore - gasleft();
        assertFalse(success);
        result; // silence unused
        // Cap is 20_000; allow generous overhead for the wrapping call frame.
        assertLt(gasUsed, 50_000, "tryPosition2 should be gas-bounded");
    }

    function test_gasCap_spotBalance_isBounded() public {
        uint256 gasBefore = gasleft();
        PrecompileLib.trySpotBalance(address(0xBEEF), 0);
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 50_000, "trySpotBalance should be gas-bounded");
    }
}
