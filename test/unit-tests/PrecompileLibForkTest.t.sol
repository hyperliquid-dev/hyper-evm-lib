// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {HyperliquidForkFixture} from "../utils/HyperliquidForkFixture.sol";

/// @notice End-to-end fork tests that exercise PrecompileLib readers against the real
///         HyperEVM chain via an FFI-based mock etched at every precompile address.
/// @dev Validates two things that simulator-based tests cannot:
///        1. Real precompile output decodes correctly into PrecompileLib structs.
///        2. The gas caps on capped staticcalls are large enough for real responses.
///      Gated behind the `ffi` foundry profile: run with `FOUNDRY_PROFILE=ffi forge test`.
///      Requires `cast` in PATH (standard Foundry install).
contract PrecompileLibForkTest is Test {
    address constant ZERO = address(0);
    uint32 constant BTC_PERP = 0;
    uint64 constant USDC_TOKEN = 0;

    function setUp() public {
        // Gated to the `ffi` profile so default `forge test` doesn't shell out.
        // Run with: `FOUNDRY_PROFILE=ffi forge test --match-contract PrecompileLibForkTest`
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string(""));
        if (keccak256(bytes(profile)) != keccak256(bytes("ffi"))) {
            vm.skip(true);
            return;
        }
        HyperliquidForkFixture.setUpLatest();
    }

    // ============ Capped gas paths ============

    function test_fork_position2() public view {
        PrecompileLib.tryPosition2(ZERO, BTC_PERP);
    }

    function test_fork_positionLegacy() public view {
        PrecompileLib.tryPositionLegacy(ZERO, uint16(BTC_PERP));
    }

    function test_fork_spotBalance() public view {
        PrecompileLib.spotBalance(ZERO, USDC_TOKEN);
    }

    function test_fork_userVaultEquity_revertsOnZeroVault() public {
        vm.expectRevert(PrecompileLib.PrecompileLib__VaultEquityPrecompileFailed.selector);
        this.callUserVaultEquity(ZERO, ZERO);
    }

    // External wrapper: forces a new call frame so `vm.expectRevert` accounting
    // isn't disturbed by the FFI mock's `pauseGasMetering`/`resumeGasMetering`.
    function callUserVaultEquity(address user, address vault) external view {
        PrecompileLib.userVaultEquity(user, vault);
    }

    function test_fork_withdrawable() public view {
        PrecompileLib.withdrawable(ZERO);
    }

    function test_fork_delegatorSummary() public view {
        PrecompileLib.delegatorSummary(ZERO);
    }

    function test_fork_markPx() public view {
        PrecompileLib.markPx(BTC_PERP);
    }

    function test_fork_oraclePx() public view {
        PrecompileLib.oraclePx(BTC_PERP);
    }

    function test_fork_spotPx() public view {
        PrecompileLib.spotPx(BTC_PERP);
    }

    function test_fork_l1BlockNumber() public view {
        PrecompileLib.l1BlockNumber();
    }

    function test_fork_bbo() public view {
        PrecompileLib.bbo(uint64(BTC_PERP));
    }

    function test_fork_accountMarginSummary() public view {
        PrecompileLib.tryAccountMarginSummary(0, ZERO);
    }

    function test_fork_coreUserExists() public view {
        PrecompileLib.coreUserExists(ZERO);
    }

    function test_fork_borrowLendUserState_revertsOnZeroUser() public {
        vm.expectRevert(PrecompileLib.PrecompileLib__BorrowLendUserStatePrecompileFailed.selector);
        this.callBorrowLendUserState(ZERO, USDC_TOKEN);
    }

    function callBorrowLendUserState(address user, uint64 token) external view {
        PrecompileLib.borrowLendUserState(user, token);
    }

    function test_fork_borrowLendReserveState() public view {
        PrecompileLib.borrowLendReserveState(USDC_TOKEN);
    }

    // ============ Uncapped (dynamic output) paths ============

    function test_fork_delegations() public view {
        PrecompileLib.delegations(ZERO);
    }

    function test_fork_perpAssetInfo() public view {
        PrecompileLib.perpAssetInfo(BTC_PERP);
    }

    function test_fork_spotInfo() public view {
        // first listed spot pair (PURR/USDC)
        PrecompileLib.spotInfo(uint64(0));
    }

    function test_fork_tokenInfo() public view {
        PrecompileLib.tokenInfo(USDC_TOKEN);
    }

    function test_fork_tokenSupply() public view {
        PrecompileLib.tokenSupply(USDC_TOKEN);
    }
}
