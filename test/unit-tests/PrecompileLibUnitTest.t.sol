// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";

/// @notice Mock-based unit tests covering every `PrecompileLib` reader.
/// @dev For each reader: (1) happy path via `vm.expectCall` + `vm.mockCall` verifies
///      the precompile is called with the exact ABI-encoded input and the decoded
///      output is wired through correctly; (2) failure path via `vm.mockCallRevert`
///      verifies the reverting variant surfaces the typed `PrecompileLib__*Failed`
///      error and the `try*` variant returns `(zeroed, false)`.
///      Complementary to `UpstreamFeaturesTest` (etched-revert failure paths) and
///      `PrecompileLibForkTest` (end-to-end gas-cap validation against real chain).
contract PrecompileLibUnitTest is Test {
    function _setupMockPrecompile(address precompileAddr, bytes memory expectedCalldata, bytes memory returnData)
        internal
    {
        vm.expectCall(precompileAddr, expectedCalldata);
        vm.mockCall(precompileAddr, expectedCalldata, returnData);
    }

    function _setupFailingPrecompile(address precompileAddr, bytes memory expectedCalldata) internal {
        vm.expectCall(precompileAddr, expectedCalldata);
        vm.mockCallRevert(precompileAddr, expectedCalldata, abi.encode("Precompile call failed"));
    }

    /*//////////////////////////////////////////////////////////////
                              position2 (0x813)
    //////////////////////////////////////////////////////////////*/

    function test_position2() public {
        address user = makeAddr("user");
        uint32 perp = 65_535;
        PrecompileLib.Position memory expected = PrecompileLib.Position({
            szi: -4321, entryNtl: 75_000, isolatedRawUsd: -1000, leverage: 5, isIsolated: false
        });

        bytes memory cd = abi.encode(user, perp);
        _setupMockPrecompile(HLConstants.POSITION2_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.Position memory result = PrecompileLib.position2(user, perp);
        assertEq(result.szi, expected.szi);
        assertEq(result.entryNtl, expected.entryNtl);
        assertEq(result.isolatedRawUsd, expected.isolatedRawUsd);
        assertEq(result.leverage, expected.leverage);
        assertEq(result.isIsolated, expected.isIsolated);
    }

    function test_position2_Fail() public {
        address user = makeAddr("user");
        uint32 perp = 65_535;
        bytes memory cd = abi.encode(user, perp);
        _setupFailingPrecompile(HLConstants.POSITION2_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__Position2PrecompileFailed.selector);
        this.callPosition2(user, perp);
    }

    function test_tryPosition2_success() public {
        address user = makeAddr("user");
        uint32 perp = 65_535;
        PrecompileLib.Position memory expected = PrecompileLib.Position({
            szi: -4321, entryNtl: 75_000, isolatedRawUsd: -1000, leverage: 5, isIsolated: false
        });

        bytes memory cd = abi.encode(user, perp);
        _setupMockPrecompile(HLConstants.POSITION2_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPosition2(user, perp);
        assertTrue(success);
        assertEq(result.szi, expected.szi);
        assertEq(result.entryNtl, expected.entryNtl);
    }

    function test_tryPosition2_fail() public {
        address user = makeAddr("user");
        uint32 perp = 65_535;
        bytes memory cd = abi.encode(user, perp);
        _setupFailingPrecompile(HLConstants.POSITION2_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPosition2(user, perp);
        assertFalse(success);
        assertEq(result.szi, 0);
        assertEq(result.entryNtl, 0);
    }

    function callPosition2(address user, uint32 perp) external view {
        PrecompileLib.position2(user, perp);
    }

    /*//////////////////////////////////////////////////////////////
                          positionLegacy (0x800)
    //////////////////////////////////////////////////////////////*/

    function test_positionLegacy() public {
        address user = makeAddr("user");
        uint16 perp = 1;
        PrecompileLib.Position memory expected =
            PrecompileLib.Position({szi: 1000, entryNtl: 50_000, isolatedRawUsd: 2000, leverage: 10, isIsolated: true});

        bytes memory cd = abi.encode(user, perp);
        _setupMockPrecompile(HLConstants.POSITION_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.Position memory result = PrecompileLib.positionLegacy(user, perp);
        assertEq(result.szi, expected.szi);
        assertEq(result.entryNtl, expected.entryNtl);
        assertEq(result.leverage, expected.leverage);
        assertEq(result.isIsolated, expected.isIsolated);
    }

    function test_positionLegacy_Fail() public {
        address user = makeAddr("user");
        uint16 perp = 1;
        bytes memory cd = abi.encode(user, perp);
        _setupFailingPrecompile(HLConstants.POSITION_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__PositionPrecompileFailed.selector);
        this.callPositionLegacy(user, perp);
    }

    function test_tryPositionLegacy_success() public {
        address user = makeAddr("user");
        uint16 perp = 1;
        PrecompileLib.Position memory expected =
            PrecompileLib.Position({szi: 1000, entryNtl: 50_000, isolatedRawUsd: 2000, leverage: 10, isIsolated: true});

        bytes memory cd = abi.encode(user, perp);
        _setupMockPrecompile(HLConstants.POSITION_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPositionLegacy(user, perp);
        assertTrue(success);
        assertEq(result.szi, expected.szi);
    }

    function test_tryPositionLegacy_fail() public {
        address user = makeAddr("user");
        uint16 perp = 1;
        bytes memory cd = abi.encode(user, perp);
        _setupFailingPrecompile(HLConstants.POSITION_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.Position memory result, bool success) = PrecompileLib.tryPositionLegacy(user, perp);
        assertFalse(success);
        assertEq(result.szi, 0);
    }

    function callPositionLegacy(address user, uint16 perp) external view {
        PrecompileLib.positionLegacy(user, perp);
    }

    /*//////////////////////////////////////////////////////////////
                              spotBalance
    //////////////////////////////////////////////////////////////*/

    function test_spotBalance() public {
        address user = makeAddr("user");
        uint64 token = 42;
        PrecompileLib.SpotBalance memory expected =
            PrecompileLib.SpotBalance({total: 10_000, hold: 5000, entryNtl: 25_000});

        bytes memory cd = abi.encode(user, token);
        _setupMockPrecompile(HLConstants.SPOT_BALANCE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.SpotBalance memory result = PrecompileLib.spotBalance(user, token);
        assertEq(result.total, expected.total);
        assertEq(result.hold, expected.hold);
        assertEq(result.entryNtl, expected.entryNtl);
    }

    function test_spotBalance_Fail() public {
        address user = makeAddr("user");
        uint64 token = 42;
        bytes memory cd = abi.encode(user, token);
        _setupFailingPrecompile(HLConstants.SPOT_BALANCE_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__SpotBalancePrecompileFailed.selector);
        this.callSpotBalance(user, token);
    }

    function test_trySpotBalance_success() public {
        address user = makeAddr("user");
        uint64 token = 42;
        PrecompileLib.SpotBalance memory expected =
            PrecompileLib.SpotBalance({total: 10_000, hold: 5000, entryNtl: 25_000});

        bytes memory cd = abi.encode(user, token);
        _setupMockPrecompile(HLConstants.SPOT_BALANCE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.SpotBalance memory result, bool success) = PrecompileLib.trySpotBalance(user, token);
        assertTrue(success);
        assertEq(result.total, expected.total);
        assertEq(result.hold, expected.hold);
        assertEq(result.entryNtl, expected.entryNtl);
    }

    function callSpotBalance(address user, uint64 token) external view {
        PrecompileLib.spotBalance(user, token);
    }

    /*//////////////////////////////////////////////////////////////
                            userVaultEquity
    //////////////////////////////////////////////////////////////*/

    function test_userVaultEquity() public {
        address user = makeAddr("user");
        address vault = makeAddr("vault");
        PrecompileLib.UserVaultEquity memory expected =
            PrecompileLib.UserVaultEquity({equity: 1_000_000, lockedUntilTimestamp: 1_234_567_890});

        bytes memory cd = abi.encode(user, vault);
        _setupMockPrecompile(HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.UserVaultEquity memory result = PrecompileLib.userVaultEquity(user, vault);
        assertEq(result.equity, expected.equity);
        assertEq(result.lockedUntilTimestamp, expected.lockedUntilTimestamp);
    }

    function test_userVaultEquity_Fail() public {
        address user = makeAddr("user");
        address vault = makeAddr("vault");
        bytes memory cd = abi.encode(user, vault);
        _setupFailingPrecompile(HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__VaultEquityPrecompileFailed.selector);
        this.callUserVaultEquity(user, vault);
    }

    function test_tryUserVaultEquity_success() public {
        address user = makeAddr("user");
        address vault = makeAddr("vault");
        PrecompileLib.UserVaultEquity memory expected =
            PrecompileLib.UserVaultEquity({equity: 1_000_000, lockedUntilTimestamp: 1_234_567_890});

        bytes memory cd = abi.encode(user, vault);
        _setupMockPrecompile(HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.UserVaultEquity memory result, bool success) = PrecompileLib.tryUserVaultEquity(user, vault);
        assertTrue(success);
        assertEq(result.equity, expected.equity);
        assertEq(result.lockedUntilTimestamp, expected.lockedUntilTimestamp);
    }

    function callUserVaultEquity(address user, address vault) external view {
        PrecompileLib.userVaultEquity(user, vault);
    }

    /*//////////////////////////////////////////////////////////////
                              withdrawable
        Library decodes to Withdrawable struct then returns the
        single uint64 field — mock encodes the struct so the
        struct decode in the library succeeds.
    //////////////////////////////////////////////////////////////*/

    function test_withdrawable() public {
        address user = makeAddr("user");
        PrecompileLib.Withdrawable memory expected = PrecompileLib.Withdrawable({withdrawable: 500_000});

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.WITHDRAWABLE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        uint64 result = PrecompileLib.withdrawable(user);
        assertEq(result, expected.withdrawable);
    }

    function test_withdrawable_Fail() public {
        address user = makeAddr("user");
        bytes memory cd = abi.encode(user);
        _setupFailingPrecompile(HLConstants.WITHDRAWABLE_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__WithdrawablePrecompileFailed.selector);
        this.callWithdrawable(user);
    }

    function test_tryWithdrawable_success() public {
        address user = makeAddr("user");
        PrecompileLib.Withdrawable memory expected = PrecompileLib.Withdrawable({withdrawable: 500_000});

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.WITHDRAWABLE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (uint64 result, bool success) = PrecompileLib.tryWithdrawable(user);
        assertTrue(success);
        assertEq(result, expected.withdrawable);
    }

    function callWithdrawable(address user) external view {
        PrecompileLib.withdrawable(user);
    }

    /*//////////////////////////////////////////////////////////////
                              delegations
    //////////////////////////////////////////////////////////////*/

    function test_delegations() public {
        address user = makeAddr("user");
        PrecompileLib.Delegation[] memory expected = new PrecompileLib.Delegation[](2);
        expected[0] = PrecompileLib.Delegation({
            validator: makeAddr("validator1"), amount: 1000, lockedUntilTimestamp: 1_234_567_890
        });
        expected[1] = PrecompileLib.Delegation({
            validator: makeAddr("validator2"), amount: 2000, lockedUntilTimestamp: 1_234_567_900
        });

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.Delegation[] memory result = PrecompileLib.delegations(user);
        assertEq(result.length, 2);
        assertEq(result[0].validator, expected[0].validator);
        assertEq(result[0].amount, expected[0].amount);
        assertEq(result[1].validator, expected[1].validator);
        assertEq(result[1].amount, expected[1].amount);
    }

    function test_delegations_Empty() public {
        address user = makeAddr("user");
        PrecompileLib.Delegation[] memory expected = new PrecompileLib.Delegation[](0);

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.Delegation[] memory result = PrecompileLib.delegations(user);
        assertEq(result.length, 0);
    }

    function test_delegations_Fail() public {
        address user = makeAddr("user");
        bytes memory cd = abi.encode(user);
        _setupFailingPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__DelegationsPrecompileFailed.selector);
        this.callDelegations(user);
    }

    function test_tryDelegations_success() public {
        address user = makeAddr("user");
        PrecompileLib.Delegation[] memory expected = new PrecompileLib.Delegation[](1);
        expected[0] = PrecompileLib.Delegation({
            validator: makeAddr("validator1"), amount: 1000, lockedUntilTimestamp: 1_234_567_890
        });

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.Delegation[] memory result, bool success) = PrecompileLib.tryDelegations(user);
        assertTrue(success);
        assertEq(result.length, 1);
        assertEq(result[0].validator, expected[0].validator);
    }

    function callDelegations(address user) external view {
        PrecompileLib.delegations(user);
    }

    /*//////////////////////////////////////////////////////////////
                          delegatorSummary
    //////////////////////////////////////////////////////////////*/

    function test_delegatorSummary() public {
        address user = makeAddr("user");
        PrecompileLib.DelegatorSummary memory expected = PrecompileLib.DelegatorSummary({
            delegated: 10_000, undelegated: 5000, totalPendingWithdrawal: 2000, nPendingWithdrawals: 3
        });

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.DelegatorSummary memory result = PrecompileLib.delegatorSummary(user);
        assertEq(result.delegated, expected.delegated);
        assertEq(result.undelegated, expected.undelegated);
        assertEq(result.totalPendingWithdrawal, expected.totalPendingWithdrawal);
        assertEq(result.nPendingWithdrawals, expected.nPendingWithdrawals);
    }

    function test_delegatorSummary_Fail() public {
        address user = makeAddr("user");
        bytes memory cd = abi.encode(user);
        _setupFailingPrecompile(HLConstants.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__DelegatorSummaryPrecompileFailed.selector);
        this.callDelegatorSummary(user);
    }

    function test_tryDelegatorSummary_success() public {
        address user = makeAddr("user");
        PrecompileLib.DelegatorSummary memory expected = PrecompileLib.DelegatorSummary({
            delegated: 10_000, undelegated: 5000, totalPendingWithdrawal: 2000, nPendingWithdrawals: 3
        });

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.DelegatorSummary memory result, bool success) = PrecompileLib.tryDelegatorSummary(user);
        assertTrue(success);
        assertEq(result.delegated, expected.delegated);
        assertEq(result.undelegated, expected.undelegated);
    }

    function callDelegatorSummary(address user) external view {
        PrecompileLib.delegatorSummary(user);
    }

    /*//////////////////////////////////////////////////////////////
                                markPx
    //////////////////////////////////////////////////////////////*/

    function test_markPx() public {
        uint32 index = 1;
        uint64 expected = 100_000_000;

        bytes memory cd = abi.encode(index);
        _setupMockPrecompile(HLConstants.MARK_PX_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        uint64 result = PrecompileLib.markPx(index);
        assertEq(result, expected);
    }

    function test_markPx_Fail() public {
        uint32 index = 1;
        bytes memory cd = abi.encode(index);
        _setupFailingPrecompile(HLConstants.MARK_PX_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__MarkPxPrecompileFailed.selector);
        this.callMarkPx(index);
    }

    function test_tryMarkPx_success() public {
        uint32 index = 1;
        uint64 expected = 100_000_000;

        bytes memory cd = abi.encode(index);
        _setupMockPrecompile(HLConstants.MARK_PX_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (uint64 result, bool success) = PrecompileLib.tryMarkPx(index);
        assertTrue(success);
        assertEq(result, expected);
    }

    function callMarkPx(uint32 index) external view {
        PrecompileLib.markPx(index);
    }

    /*//////////////////////////////////////////////////////////////
                                oraclePx
    //////////////////////////////////////////////////////////////*/

    function test_oraclePx() public {
        uint32 index = 1;
        uint64 expected = 99_500_000;

        bytes memory cd = abi.encode(index);
        _setupMockPrecompile(HLConstants.ORACLE_PX_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        uint64 result = PrecompileLib.oraclePx(index);
        assertEq(result, expected);
    }

    function test_oraclePx_Fail() public {
        uint32 index = 1;
        bytes memory cd = abi.encode(index);
        _setupFailingPrecompile(HLConstants.ORACLE_PX_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__OraclePxPrecompileFailed.selector);
        this.callOraclePx(index);
    }

    function test_tryOraclePx_success() public {
        uint32 index = 1;
        uint64 expected = 99_500_000;

        bytes memory cd = abi.encode(index);
        _setupMockPrecompile(HLConstants.ORACLE_PX_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (uint64 result, bool success) = PrecompileLib.tryOraclePx(index);
        assertTrue(success);
        assertEq(result, expected);
    }

    function callOraclePx(uint32 index) external view {
        PrecompileLib.oraclePx(index);
    }

    /*//////////////////////////////////////////////////////////////
                                spotPx
    //////////////////////////////////////////////////////////////*/

    function test_spotPx() public {
        uint64 index = 1;
        uint64 expected = 98_000_000;

        bytes memory cd = abi.encode(index);
        _setupMockPrecompile(HLConstants.SPOT_PX_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        uint64 result = PrecompileLib.spotPx(index);
        assertEq(result, expected);
    }

    function test_spotPx_Fail() public {
        uint64 index = 1;
        bytes memory cd = abi.encode(index);
        _setupFailingPrecompile(HLConstants.SPOT_PX_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__SpotPxPrecompileFailed.selector);
        this.callSpotPx(index);
    }

    function test_trySpotPx_success() public {
        uint64 index = 1;
        uint64 expected = 98_000_000;

        bytes memory cd = abi.encode(index);
        _setupMockPrecompile(HLConstants.SPOT_PX_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (uint64 result, bool success) = PrecompileLib.trySpotPx(index);
        assertTrue(success);
        assertEq(result, expected);
    }

    function callSpotPx(uint64 index) external view {
        PrecompileLib.spotPx(index);
    }

    /*//////////////////////////////////////////////////////////////
                            l1BlockNumber
    //////////////////////////////////////////////////////////////*/

    function test_l1BlockNumber() public {
        uint64 expected = 12_345;
        bytes memory cd = "";
        _setupMockPrecompile(HLConstants.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        uint64 result = PrecompileLib.l1BlockNumber();
        assertEq(result, expected);
    }

    function test_l1BlockNumber_Fail() public {
        bytes memory cd = "";
        _setupFailingPrecompile(HLConstants.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__L1BlockNumberPrecompileFailed.selector);
        this.callL1BlockNumber();
    }

    function test_tryL1BlockNumber_success() public {
        uint64 expected = 12_345;
        bytes memory cd = "";
        _setupMockPrecompile(HLConstants.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (uint64 result, bool success) = PrecompileLib.tryL1BlockNumber();
        assertTrue(success);
        assertEq(result, expected);
    }

    function callL1BlockNumber() external view {
        PrecompileLib.l1BlockNumber();
    }

    /*//////////////////////////////////////////////////////////////
                            perpAssetInfo
    //////////////////////////////////////////////////////////////*/

    function test_perpAssetInfo() public {
        uint32 perp = 1;
        PrecompileLib.PerpAssetInfo memory expected = PrecompileLib.PerpAssetInfo({
            coin: "BTC", marginTableId: 10, szDecimals: 8, maxLeverage: 20, onlyIsolated: false
        });

        bytes memory cd = abi.encode(perp);
        _setupMockPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.PerpAssetInfo memory result = PrecompileLib.perpAssetInfo(perp);
        assertEq(keccak256(bytes(result.coin)), keccak256(bytes(expected.coin)));
        assertEq(result.marginTableId, expected.marginTableId);
        assertEq(result.szDecimals, expected.szDecimals);
        assertEq(result.maxLeverage, expected.maxLeverage);
        assertEq(result.onlyIsolated, expected.onlyIsolated);
    }

    function test_perpAssetInfo_Fail() public {
        uint32 perp = 1;
        bytes memory cd = abi.encode(perp);
        _setupFailingPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__PerpAssetInfoPrecompileFailed.selector);
        this.callPerpAssetInfo(perp);
    }

    function test_tryPerpAssetInfo_success() public {
        uint32 perp = 1;
        PrecompileLib.PerpAssetInfo memory expected = PrecompileLib.PerpAssetInfo({
            coin: "BTC", marginTableId: 10, szDecimals: 8, maxLeverage: 20, onlyIsolated: false
        });

        bytes memory cd = abi.encode(perp);
        _setupMockPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.PerpAssetInfo memory result, bool success) = PrecompileLib.tryPerpAssetInfo(perp);
        assertTrue(success);
        assertEq(keccak256(bytes(result.coin)), keccak256(bytes(expected.coin)));
        assertEq(result.maxLeverage, expected.maxLeverage);
    }

    function test_tryPerpAssetInfo_fail() public {
        uint32 perp = 1;
        bytes memory cd = abi.encode(perp);
        _setupFailingPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.PerpAssetInfo memory result, bool success) = PrecompileLib.tryPerpAssetInfo(perp);
        assertFalse(success);
        assertEq(bytes(result.coin).length, 0);
        assertEq(result.maxLeverage, 0);
    }

    function callPerpAssetInfo(uint32 perp) external view {
        PrecompileLib.perpAssetInfo(perp);
    }

    /*//////////////////////////////////////////////////////////////
                              spotInfo
    //////////////////////////////////////////////////////////////*/

    function test_spotInfo() public {
        uint64 spot = 1;
        PrecompileLib.SpotInfo memory expected =
            PrecompileLib.SpotInfo({name: "BTC/USD", tokens: [uint64(1), uint64(2)]});

        bytes memory cd = abi.encode(spot);
        _setupMockPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.SpotInfo memory result = PrecompileLib.spotInfo(spot);
        assertEq(keccak256(bytes(result.name)), keccak256(bytes(expected.name)));
        assertEq(result.tokens[0], expected.tokens[0]);
        assertEq(result.tokens[1], expected.tokens[1]);
    }

    function test_spotInfo_Fail() public {
        uint64 spot = 1;
        bytes memory cd = abi.encode(spot);
        _setupFailingPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__SpotInfoPrecompileFailed.selector);
        this.callSpotInfo(spot);
    }

    function test_trySpotInfo_success() public {
        uint64 spot = 1;
        PrecompileLib.SpotInfo memory expected =
            PrecompileLib.SpotInfo({name: "BTC/USD", tokens: [uint64(1), uint64(2)]});

        bytes memory cd = abi.encode(spot);
        _setupMockPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.SpotInfo memory result, bool success) = PrecompileLib.trySpotInfo(spot);
        assertTrue(success);
        assertEq(keccak256(bytes(result.name)), keccak256(bytes(expected.name)));
        assertEq(result.tokens[0], expected.tokens[0]);
    }

    function test_trySpotInfo_fail() public {
        uint64 spot = 1;
        bytes memory cd = abi.encode(spot);
        _setupFailingPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.SpotInfo memory result, bool success) = PrecompileLib.trySpotInfo(spot);
        assertFalse(success);
        assertEq(bytes(result.name).length, 0);
        assertEq(result.tokens[0], 0);
        assertEq(result.tokens[1], 0);
    }

    function callSpotInfo(uint64 spot) external view {
        PrecompileLib.spotInfo(spot);
    }

    /*//////////////////////////////////////////////////////////////
                              tokenInfo
    //////////////////////////////////////////////////////////////*/

    function test_tokenInfo() public {
        uint64 token = 1;
        uint64[] memory spots = new uint64[](2);
        spots[0] = 1;
        spots[1] = 2;
        PrecompileLib.TokenInfo memory expected = PrecompileLib.TokenInfo({
            name: "Bitcoin",
            spots: spots,
            deployerTradingFeeShare: 100,
            deployer: makeAddr("deployer"),
            evmContract: makeAddr("evmContract"),
            szDecimals: 8,
            weiDecimals: 18,
            evmExtraWeiDecimals: 0
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.TokenInfo memory result = PrecompileLib.tokenInfo(token);
        assertEq(keccak256(bytes(result.name)), keccak256(bytes(expected.name)));
        assertEq(result.spots.length, expected.spots.length);
        assertEq(result.deployerTradingFeeShare, expected.deployerTradingFeeShare);
        assertEq(result.deployer, expected.deployer);
        assertEq(result.evmContract, expected.evmContract);
        assertEq(result.szDecimals, expected.szDecimals);
        assertEq(result.weiDecimals, expected.weiDecimals);
        assertEq(result.evmExtraWeiDecimals, expected.evmExtraWeiDecimals);
    }

    function test_tokenInfo_Fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__TokenInfoPrecompileFailed.selector);
        this.callTokenInfo(token);
    }

    function test_tryTokenInfo_success() public {
        uint64 token = 1;
        uint64[] memory spots = new uint64[](2);
        spots[0] = 1;
        spots[1] = 2;
        PrecompileLib.TokenInfo memory expected = PrecompileLib.TokenInfo({
            name: "Bitcoin",
            spots: spots,
            deployerTradingFeeShare: 100,
            deployer: makeAddr("deployer"),
            evmContract: makeAddr("evmContract"),
            szDecimals: 8,
            weiDecimals: 18,
            evmExtraWeiDecimals: 0
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.TokenInfo memory result, bool success) = PrecompileLib.tryTokenInfo(token);
        assertTrue(success);
        assertEq(keccak256(bytes(result.name)), keccak256(bytes(expected.name)));
        assertEq(result.spots.length, 2);
    }

    function test_tryTokenInfo_fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.TokenInfo memory result, bool success) = PrecompileLib.tryTokenInfo(token);
        assertFalse(success);
        assertEq(bytes(result.name).length, 0);
        assertEq(result.spots.length, 0);
        assertEq(result.deployer, address(0));
    }

    function callTokenInfo(uint64 token) external view {
        PrecompileLib.tokenInfo(token);
    }

    /*//////////////////////////////////////////////////////////////
                              tokenSupply
    //////////////////////////////////////////////////////////////*/

    function test_tokenSupply() public {
        uint64 token = 1;
        PrecompileLib.UserBalance[] memory nonCirculating = new PrecompileLib.UserBalance[](1);
        nonCirculating[0] = PrecompileLib.UserBalance({user: makeAddr("user"), balance: 1000});
        PrecompileLib.TokenSupply memory expected = PrecompileLib.TokenSupply({
            maxSupply: 21_000_000,
            totalSupply: 19_000_000,
            circulatingSupply: 18_999_000,
            futureEmissions: 500_000,
            nonCirculatingUserBalances: nonCirculating
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.TokenSupply memory result = PrecompileLib.tokenSupply(token);
        assertEq(result.maxSupply, expected.maxSupply);
        assertEq(result.totalSupply, expected.totalSupply);
        assertEq(result.circulatingSupply, expected.circulatingSupply);
        assertEq(result.futureEmissions, expected.futureEmissions);
        assertEq(result.nonCirculatingUserBalances.length, expected.nonCirculatingUserBalances.length);
        assertEq(result.nonCirculatingUserBalances[0].user, expected.nonCirculatingUserBalances[0].user);
        assertEq(result.nonCirculatingUserBalances[0].balance, expected.nonCirculatingUserBalances[0].balance);
    }

    function test_tokenSupply_Fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__TokenSupplyPrecompileFailed.selector);
        this.callTokenSupply(token);
    }

    function test_tryTokenSupply_success() public {
        uint64 token = 1;
        PrecompileLib.UserBalance[] memory nonCirculating = new PrecompileLib.UserBalance[](1);
        nonCirculating[0] = PrecompileLib.UserBalance({user: makeAddr("user"), balance: 1000});
        PrecompileLib.TokenSupply memory expected = PrecompileLib.TokenSupply({
            maxSupply: 21_000_000,
            totalSupply: 19_000_000,
            circulatingSupply: 18_999_000,
            futureEmissions: 500_000,
            nonCirculatingUserBalances: nonCirculating
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.TokenSupply memory result, bool success) = PrecompileLib.tryTokenSupply(token);
        assertTrue(success);
        assertEq(result.maxSupply, expected.maxSupply);
        assertEq(result.nonCirculatingUserBalances.length, 1);
    }

    function test_tryTokenSupply_fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.TokenSupply memory result, bool success) = PrecompileLib.tryTokenSupply(token);
        assertFalse(success);
        assertEq(result.maxSupply, 0);
        assertEq(result.totalSupply, 0);
        assertEq(result.nonCirculatingUserBalances.length, 0);
    }

    function callTokenSupply(uint64 token) external view {
        PrecompileLib.tokenSupply(token);
    }

    /*//////////////////////////////////////////////////////////////
                                  bbo
    //////////////////////////////////////////////////////////////*/

    function test_bbo() public {
        uint64 asset = 1;
        PrecompileLib.Bbo memory expected = PrecompileLib.Bbo({bid: 99_500_000, ask: 100_500_000});

        bytes memory cd = abi.encode(asset);
        _setupMockPrecompile(HLConstants.BBO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.Bbo memory result = PrecompileLib.bbo(asset);
        assertEq(result.bid, expected.bid);
        assertEq(result.ask, expected.ask);
    }

    function test_bbo_Fail() public {
        uint64 asset = 1;
        bytes memory cd = abi.encode(asset);
        _setupFailingPrecompile(HLConstants.BBO_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__BboPrecompileFailed.selector);
        this.callBbo(asset);
    }

    function test_tryBbo_success() public {
        uint64 asset = 1;
        PrecompileLib.Bbo memory expected = PrecompileLib.Bbo({bid: 99_500_000, ask: 100_500_000});

        bytes memory cd = abi.encode(asset);
        _setupMockPrecompile(HLConstants.BBO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.Bbo memory result, bool success) = PrecompileLib.tryBbo(asset);
        assertTrue(success);
        assertEq(result.bid, expected.bid);
        assertEq(result.ask, expected.ask);
    }

    function callBbo(uint64 asset) external view {
        PrecompileLib.bbo(asset);
    }

    /*//////////////////////////////////////////////////////////////
                        accountMarginSummary
    //////////////////////////////////////////////////////////////*/

    function test_accountMarginSummary() public {
        uint32 perpDexIndex = 1;
        address user = makeAddr("user");
        PrecompileLib.AccountMarginSummary memory expected = PrecompileLib.AccountMarginSummary({
            accountValue: 1_000_000, marginUsed: 500_000, ntlPos: 2_000_000, rawUsd: 800_000
        });

        bytes memory cd = abi.encode(perpDexIndex, user);
        _setupMockPrecompile(HLConstants.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.AccountMarginSummary memory result = PrecompileLib.accountMarginSummary(perpDexIndex, user);
        assertEq(result.accountValue, expected.accountValue);
        assertEq(result.marginUsed, expected.marginUsed);
        assertEq(result.ntlPos, expected.ntlPos);
        assertEq(result.rawUsd, expected.rawUsd);
    }

    function test_accountMarginSummary_Fail() public {
        uint32 perpDexIndex = 1;
        address user = makeAddr("user");
        bytes memory cd = abi.encode(perpDexIndex, user);
        _setupFailingPrecompile(HLConstants.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__AccountMarginSummaryPrecompileFailed.selector);
        this.callAccountMarginSummary(perpDexIndex, user);
    }

    function test_tryAccountMarginSummary_success() public {
        uint32 perpDexIndex = 1;
        address user = makeAddr("user");
        PrecompileLib.AccountMarginSummary memory expected = PrecompileLib.AccountMarginSummary({
            accountValue: 1_000_000, marginUsed: 500_000, ntlPos: 2_000_000, rawUsd: 800_000
        });

        bytes memory cd = abi.encode(perpDexIndex, user);
        _setupMockPrecompile(HLConstants.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.AccountMarginSummary memory result, bool success) =
            PrecompileLib.tryAccountMarginSummary(perpDexIndex, user);
        assertTrue(success);
        assertEq(result.accountValue, expected.accountValue);
        assertEq(result.marginUsed, expected.marginUsed);
    }

    function callAccountMarginSummary(uint32 perpDexIndex, address user) external view {
        PrecompileLib.accountMarginSummary(perpDexIndex, user);
    }

    /*//////////////////////////////////////////////////////////////
                            coreUserExists
        Library decodes to CoreUserExists struct then returns the
        single bool field — mock encodes the struct.
    //////////////////////////////////////////////////////////////*/

    function test_coreUserExists_true() public {
        address user = makeAddr("user");
        PrecompileLib.CoreUserExists memory expected = PrecompileLib.CoreUserExists({exists: true});

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        bool result = PrecompileLib.coreUserExists(user);
        assertTrue(result);
    }

    function test_coreUserExists_false() public {
        address user = makeAddr("user");
        PrecompileLib.CoreUserExists memory expected = PrecompileLib.CoreUserExists({exists: false});

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        bool result = PrecompileLib.coreUserExists(user);
        assertFalse(result);
    }

    function test_coreUserExists_Fail() public {
        address user = makeAddr("user");
        bytes memory cd = abi.encode(user);
        _setupFailingPrecompile(HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__CoreUserExistsPrecompileFailed.selector);
        this.callCoreUserExists(user);
    }

    function test_tryCoreUserExists_success() public {
        address user = makeAddr("user");
        PrecompileLib.CoreUserExists memory expected = PrecompileLib.CoreUserExists({exists: true});

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (bool exists, bool success) = PrecompileLib.tryCoreUserExists(user);
        assertTrue(success);
        assertTrue(exists);
    }

    function callCoreUserExists(address user) external view {
        PrecompileLib.coreUserExists(user);
    }

    /*//////////////////////////////////////////////////////////////
                        borrowLendUserState
    //////////////////////////////////////////////////////////////*/

    function test_borrowLendUserState() public {
        address user = makeAddr("user");
        uint64 token = 1;
        PrecompileLib.BorrowLendUserTokenState memory expected = PrecompileLib.BorrowLendUserTokenState({
            borrow: PrecompileLib.BasisAndValue({basis: 1000, value: 2000}),
            supply: PrecompileLib.BasisAndValue({basis: 5000, value: 10_000})
        });

        bytes memory cd = abi.encode(user, token);
        _setupMockPrecompile(HLConstants.BORROW_LEND_USER_STATE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.BorrowLendUserTokenState memory result = PrecompileLib.borrowLendUserState(user, token);
        assertEq(result.borrow.basis, expected.borrow.basis);
        assertEq(result.borrow.value, expected.borrow.value);
        assertEq(result.supply.basis, expected.supply.basis);
        assertEq(result.supply.value, expected.supply.value);
    }

    function test_borrowLendUserState_Fail() public {
        address user = makeAddr("user");
        uint64 token = 1;
        bytes memory cd = abi.encode(user, token);
        _setupFailingPrecompile(HLConstants.BORROW_LEND_USER_STATE_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__BorrowLendUserStatePrecompileFailed.selector);
        this.callBorrowLendUserState(user, token);
    }

    function test_tryBorrowLendUserState_success() public {
        address user = makeAddr("user");
        uint64 token = 1;
        PrecompileLib.BorrowLendUserTokenState memory expected = PrecompileLib.BorrowLendUserTokenState({
            borrow: PrecompileLib.BasisAndValue({basis: 1000, value: 2000}),
            supply: PrecompileLib.BasisAndValue({basis: 5000, value: 10_000})
        });

        bytes memory cd = abi.encode(user, token);
        _setupMockPrecompile(HLConstants.BORROW_LEND_USER_STATE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.BorrowLendUserTokenState memory result, bool success) =
            PrecompileLib.tryBorrowLendUserState(user, token);
        assertTrue(success);
        assertEq(result.borrow.basis, expected.borrow.basis);
        assertEq(result.supply.value, expected.supply.value);
    }

    function callBorrowLendUserState(address user, uint64 token) external view {
        PrecompileLib.borrowLendUserState(user, token);
    }

    /*//////////////////////////////////////////////////////////////
                      borrowLendReserveState
    //////////////////////////////////////////////////////////////*/

    function test_borrowLendReserveState() public {
        uint64 token = 1;
        PrecompileLib.BorrowLendReserveState memory expected = PrecompileLib.BorrowLendReserveState({
            borrowYearlyRateBps: 500,
            supplyYearlyRateBps: 300,
            balance: 1_000_000,
            utilizationBps: 7500,
            oraclePx: 100_000_000,
            ltvBps: 8000,
            totalSupplied: 10_000_000,
            totalBorrowed: 7_500_000
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.BORROW_LEND_RESERVE_STATE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.BorrowLendReserveState memory result = PrecompileLib.borrowLendReserveState(token);
        assertEq(result.borrowYearlyRateBps, expected.borrowYearlyRateBps);
        assertEq(result.supplyYearlyRateBps, expected.supplyYearlyRateBps);
        assertEq(result.balance, expected.balance);
        assertEq(result.utilizationBps, expected.utilizationBps);
        assertEq(result.oraclePx, expected.oraclePx);
        assertEq(result.ltvBps, expected.ltvBps);
        assertEq(result.totalSupplied, expected.totalSupplied);
        assertEq(result.totalBorrowed, expected.totalBorrowed);
    }

    function test_borrowLendReserveState_Fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.BORROW_LEND_RESERVE_STATE_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__BorrowLendReserveStatePrecompileFailed.selector);
        this.callBorrowLendReserveState(token);
    }

    function test_tryBorrowLendReserveState_success() public {
        uint64 token = 1;
        PrecompileLib.BorrowLendReserveState memory expected = PrecompileLib.BorrowLendReserveState({
            borrowYearlyRateBps: 500,
            supplyYearlyRateBps: 300,
            balance: 1_000_000,
            utilizationBps: 7500,
            oraclePx: 100_000_000,
            ltvBps: 8000,
            totalSupplied: 10_000_000,
            totalBorrowed: 7_500_000
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.BORROW_LEND_RESERVE_STATE_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.BorrowLendReserveState memory result, bool success) =
            PrecompileLib.tryBorrowLendReserveState(token);
        assertTrue(success);
        assertEq(result.borrowYearlyRateBps, expected.borrowYearlyRateBps);
        assertEq(result.totalBorrowed, expected.totalBorrowed);
    }

    function callBorrowLendReserveState(uint64 token) external view {
        PrecompileLib.borrowLendReserveState(token);
    }

    /*//////////////////////////////////////////////////////////////
              Gas-param overloads (uncapped dynamic-output readers)
    //////////////////////////////////////////////////////////////*/

    function test_tryDelegations_withGas_success() public {
        address user = makeAddr("user");
        PrecompileLib.Delegation[] memory expected = new PrecompileLib.Delegation[](1);
        expected[0] = PrecompileLib.Delegation({
            validator: makeAddr("validator1"), amount: 1000, lockedUntilTimestamp: 1_234_567_890
        });

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.Delegation[] memory result, bool success) = PrecompileLib.tryDelegations(user, 50_000);
        assertTrue(success);
        assertEq(result.length, 1);
        assertEq(result[0].validator, expected[0].validator);
    }

    function test_tryDelegations_withGas_fail() public {
        address user = makeAddr("user");
        bytes memory cd = abi.encode(user);
        _setupFailingPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.Delegation[] memory result, bool success) = PrecompileLib.tryDelegations(user, 50_000);
        assertFalse(success);
        assertEq(result.length, 0);
    }

    function test_delegations_withGas() public {
        address user = makeAddr("user");
        PrecompileLib.Delegation[] memory expected = new PrecompileLib.Delegation[](1);
        expected[0] = PrecompileLib.Delegation({
            validator: makeAddr("validator1"), amount: 1000, lockedUntilTimestamp: 1_234_567_890
        });

        bytes memory cd = abi.encode(user);
        _setupMockPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.Delegation[] memory result = PrecompileLib.delegations(user, 50_000);
        assertEq(result.length, 1);
        assertEq(result[0].validator, expected[0].validator);
    }

    function test_delegations_withGas_Fail() public {
        address user = makeAddr("user");
        bytes memory cd = abi.encode(user);
        _setupFailingPrecompile(HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS, cd);

        vm.expectRevert(PrecompileLib.PrecompileLib__DelegationsPrecompileFailed.selector);
        this.callDelegationsWithGas(user, 50_000);
    }

    function callDelegationsWithGas(address user, uint256 gas) external view {
        PrecompileLib.delegations(user, gas);
    }

    function test_tryPerpAssetInfo_withGas_success() public {
        uint32 perp = 1;
        PrecompileLib.PerpAssetInfo memory expected = PrecompileLib.PerpAssetInfo({
            coin: "BTC", marginTableId: 1, szDecimals: 4, maxLeverage: 50, onlyIsolated: false
        });

        bytes memory cd = abi.encode(perp);
        _setupMockPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.PerpAssetInfo memory result, bool success) = PrecompileLib.tryPerpAssetInfo(perp, 50_000);
        assertTrue(success);
        assertEq(result.coin, expected.coin);
        assertEq(result.maxLeverage, expected.maxLeverage);
    }

    function test_tryPerpAssetInfo_withGas_fail() public {
        uint32 perp = 1;
        bytes memory cd = abi.encode(perp);
        _setupFailingPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.PerpAssetInfo memory result, bool success) = PrecompileLib.tryPerpAssetInfo(perp, 50_000);
        assertFalse(success);
        assertEq(result.maxLeverage, 0);
        assertEq(bytes(result.coin).length, 0);
    }

    function test_perpAssetInfo_withGas() public {
        uint32 perp = 1;
        PrecompileLib.PerpAssetInfo memory expected = PrecompileLib.PerpAssetInfo({
            coin: "BTC", marginTableId: 1, szDecimals: 4, maxLeverage: 50, onlyIsolated: false
        });

        bytes memory cd = abi.encode(perp);
        _setupMockPrecompile(HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.PerpAssetInfo memory result = PrecompileLib.perpAssetInfo(perp, 50_000);
        assertEq(result.coin, expected.coin);
    }

    function test_trySpotInfo_withGas_success() public {
        uint64 spot = 1;
        uint64[2] memory tokens = [uint64(1), uint64(0)];
        PrecompileLib.SpotInfo memory expected = PrecompileLib.SpotInfo({name: "BTC/USDC", tokens: tokens});

        bytes memory cd = abi.encode(spot);
        _setupMockPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.SpotInfo memory result, bool success) = PrecompileLib.trySpotInfo(spot, 50_000);
        assertTrue(success);
        assertEq(result.name, expected.name);
        assertEq(result.tokens[0], expected.tokens[0]);
    }

    function test_trySpotInfo_withGas_fail() public {
        uint64 spot = 1;
        bytes memory cd = abi.encode(spot);
        _setupFailingPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.SpotInfo memory result, bool success) = PrecompileLib.trySpotInfo(spot, 50_000);
        assertFalse(success);
        assertEq(bytes(result.name).length, 0);
    }

    function test_spotInfo_withGas() public {
        uint64 spot = 1;
        uint64[2] memory tokens = [uint64(1), uint64(0)];
        PrecompileLib.SpotInfo memory expected = PrecompileLib.SpotInfo({name: "BTC/USDC", tokens: tokens});

        bytes memory cd = abi.encode(spot);
        _setupMockPrecompile(HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.SpotInfo memory result = PrecompileLib.spotInfo(spot, 50_000);
        assertEq(result.name, expected.name);
    }

    function test_tryTokenInfo_withGas_success() public {
        uint64 token = 1;
        uint64[] memory spots = new uint64[](1);
        spots[0] = 1;
        PrecompileLib.TokenInfo memory expected = PrecompileLib.TokenInfo({
            name: "BTC",
            spots: spots,
            deployerTradingFeeShare: 100,
            deployer: makeAddr("deployer"),
            evmContract: makeAddr("evmContract"),
            szDecimals: 4,
            weiDecimals: 8,
            evmExtraWeiDecimals: 10
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.TokenInfo memory result, bool success) = PrecompileLib.tryTokenInfo(token, 50_000);
        assertTrue(success);
        assertEq(result.name, expected.name);
        assertEq(result.evmContract, expected.evmContract);
    }

    function test_tryTokenInfo_withGas_fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.TokenInfo memory result, bool success) = PrecompileLib.tryTokenInfo(token, 50_000);
        assertFalse(success);
        assertEq(result.evmContract, address(0));
        assertEq(bytes(result.name).length, 0);
    }

    function test_tokenInfo_withGas() public {
        uint64 token = 1;
        uint64[] memory spots = new uint64[](1);
        spots[0] = 1;
        PrecompileLib.TokenInfo memory expected = PrecompileLib.TokenInfo({
            name: "BTC",
            spots: spots,
            deployerTradingFeeShare: 100,
            deployer: makeAddr("deployer"),
            evmContract: makeAddr("evmContract"),
            szDecimals: 4,
            weiDecimals: 8,
            evmExtraWeiDecimals: 10
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.TokenInfo memory result = PrecompileLib.tokenInfo(token, 50_000);
        assertEq(result.name, expected.name);
    }

    function test_tryTokenSupply_withGas_success() public {
        uint64 token = 1;
        PrecompileLib.UserBalance[] memory nonCirc = new PrecompileLib.UserBalance[](1);
        nonCirc[0] = PrecompileLib.UserBalance({user: makeAddr("treasury"), balance: 500_000});
        PrecompileLib.TokenSupply memory expected = PrecompileLib.TokenSupply({
            maxSupply: 21_000_000,
            totalSupply: 19_000_000,
            circulatingSupply: 18_000_000,
            futureEmissions: 2_000_000,
            nonCirculatingUserBalances: nonCirc
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        (PrecompileLib.TokenSupply memory result, bool success) = PrecompileLib.tryTokenSupply(token, 50_000);
        assertTrue(success);
        assertEq(result.maxSupply, expected.maxSupply);
        assertEq(result.nonCirculatingUserBalances.length, 1);
    }

    function test_tryTokenSupply_withGas_fail() public {
        uint64 token = 1;
        bytes memory cd = abi.encode(token);
        _setupFailingPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd);

        (PrecompileLib.TokenSupply memory result, bool success) = PrecompileLib.tryTokenSupply(token, 50_000);
        assertFalse(success);
        assertEq(result.maxSupply, 0);
        assertEq(result.nonCirculatingUserBalances.length, 0);
    }

    function test_tokenSupply_withGas() public {
        uint64 token = 1;
        PrecompileLib.UserBalance[] memory nonCirc = new PrecompileLib.UserBalance[](0);
        PrecompileLib.TokenSupply memory expected = PrecompileLib.TokenSupply({
            maxSupply: 21_000_000,
            totalSupply: 19_000_000,
            circulatingSupply: 18_000_000,
            futureEmissions: 2_000_000,
            nonCirculatingUserBalances: nonCirc
        });

        bytes memory cd = abi.encode(token);
        _setupMockPrecompile(HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS, cd, abi.encode(expected));

        PrecompileLib.TokenSupply memory result = PrecompileLib.tokenSupply(token, 50_000);
        assertEq(result.maxSupply, expected.maxSupply);
    }
}
