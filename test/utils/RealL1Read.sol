// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {HyperCore} from "../simulation/HyperCore.sol";

HyperCore constant hyperCore = HyperCore(payable(0x9999999999999999999999999999999999999999));

// Makes RPC calls to get real precompile data (independent of the test environment)
// During offline mode, this will call the local precompile to return local data
library RealL1Read {
    Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    address constant POSITION_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000800;
    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
    address constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
    address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;
    address constant DELEGATIONS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000804;
    address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000805;
    address constant MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;
    address constant ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
    address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
    address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;
    address constant PERP_ASSET_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080a;
    address constant SPOT_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080b;
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
    address constant TOKEN_SUPPLY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080D;
    address constant BBO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080e;
    address constant ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080F;
    address constant CORE_USER_EXISTS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000810;

    address constant INVALID_ADDRESS = address(1);

    function _makeRpcCall(address target, bytes memory params) internal returns (bytes memory) {
        // Construct the JSON-RPC payload
        string memory jsonPayload =
            string.concat('[{"to":"', vm.toString(target), '","data":"', vm.toString(params), '"},"latest"]');

        bool useArchivedBlockNumber = false;

        if (useArchivedBlockNumber) {
            string memory blockNumberHex = string.concat("0x", toHexString(block.number));

            jsonPayload = string.concat(
                '[{"to":"', vm.toString(target), '","data":"', vm.toString(params), '"},"', blockNumberHex, '"]'
            );
        }

        // Make the RPC call
        try vm.rpc("eth_call", jsonPayload) returns (bytes memory data) {
            return data;
        } catch {
            return "";
        }
    }

    function toHexString(uint256 a) internal pure returns (string memory) {
        uint256 count = 0;
        uint256 b = a;
        while (b != 0) {
            count++;
            b /= 16;
        }
        bytes memory res = new bytes(count);
        for (uint256 i = 0; i < count; ++i) {
            b = a % 16;
            res[count - i - 1] = toHexDigit(uint8(b));
            a /= 16;
        }
        return string(res);
    }

    function toHexDigit(uint8 d) internal pure returns (bytes1) {
        if (0 <= d && d <= 9) {
            return bytes1(uint8(bytes1("0")) + d);
        } else if (10 <= uint8(d) && uint8(d) <= 15) {
            return bytes1(uint8(bytes1("a")) + d - 10);
        }
        // revert("Invalid hex digit");
        revert();
    }

    function isOfflineMode() internal view returns (bool) {
        return !isForkActive() && !hyperCore.useRealL1Read();
    }

    function isForkActive() internal view returns (bool) {
        try vm.activeFork() returns (uint256) {
            return true;  // Fork is active
        } catch {
            return false; // No fork active
        }
    }

    function position(address user, uint16 perp) internal returns (PrecompileLib.Position memory) {

        if (isOfflineMode()) {
            return PrecompileLib.position(user, perp);
        }

        bytes memory result = _makeRpcCall(POSITION_PRECOMPILE_ADDRESS, abi.encode(user, perp));

        if (result.length == 0) {
            return PrecompileLib.Position({szi: 0, entryNtl: 0, isolatedRawUsd: 0, leverage: 0, isIsolated: false});
        }
        return abi.decode(result, (PrecompileLib.Position));
    }

    function spotBalance(address user, uint64 token) internal returns (PrecompileLib.SpotBalance memory) {

        if (isOfflineMode()) {
            return PrecompileLib.spotBalance(user, token);
        }

        bytes memory result = _makeRpcCall(SPOT_BALANCE_PRECOMPILE_ADDRESS, abi.encode(user, token));
        if (result.length == 0) {
            return PrecompileLib.SpotBalance({total: 0, hold: 0, entryNtl: 0});
        }
        return abi.decode(result, (PrecompileLib.SpotBalance));
    }

    function userVaultEquity(address user, address vault) internal returns (PrecompileLib.UserVaultEquity memory) {

        if (isOfflineMode()) {
            return PrecompileLib.userVaultEquity(user, vault);
        }

        bytes memory result = _makeRpcCall(VAULT_EQUITY_PRECOMPILE_ADDRESS, abi.encode(user, vault));
        if (result.length == 0) {
            return PrecompileLib.UserVaultEquity({equity: 0, lockedUntilTimestamp: 0});
        }
        return abi.decode(result, (PrecompileLib.UserVaultEquity));
    }

    function withdrawable(address user) internal returns (uint64) {

        if (isOfflineMode()) {
            return PrecompileLib.withdrawable(user);
        }

        bytes memory result = _makeRpcCall(WITHDRAWABLE_PRECOMPILE_ADDRESS, abi.encode(user));
        if (result.length == 0) {
            return 0;
        }
        return abi.decode(result, (PrecompileLib.Withdrawable)).withdrawable;
    }

    function delegations(address user) internal returns (PrecompileLib.Delegation[] memory) {

        if (isOfflineMode()) {
            return PrecompileLib.delegations(user);
        }

        bytes memory result = _makeRpcCall(DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(user));
        if (result.length == 0) {
            return new PrecompileLib.Delegation[](0);
        }
        return abi.decode(result, (PrecompileLib.Delegation[]));
    }

    function delegatorSummary(address user) internal returns (PrecompileLib.DelegatorSummary memory) {

        if (isOfflineMode()) {
            return PrecompileLib.delegatorSummary(user);
        }

        bytes memory result = _makeRpcCall(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, abi.encode(user));
        return abi.decode(result, (PrecompileLib.DelegatorSummary));
    }

    function markPx(uint32 index) internal returns (uint64) {

        if (isOfflineMode()) {
            return PrecompileLib.markPx(index);
        }

        bytes memory result = _makeRpcCall(MARK_PX_PRECOMPILE_ADDRESS, abi.encode(index));
        return abi.decode(result, (uint64));
    }

    function oraclePx(uint32 index) internal returns (uint64) {

        if (isOfflineMode()) {
            return PrecompileLib.oraclePx(index);
        }

        bytes memory result = _makeRpcCall(ORACLE_PX_PRECOMPILE_ADDRESS, abi.encode(index));
        return abi.decode(result, (uint64));
    }

    function spotPx(uint32 index) internal returns (uint64) {

        if (isOfflineMode()) {
            return PrecompileLib.spotPx(index);
        }

        bytes memory result = _makeRpcCall(SPOT_PX_PRECOMPILE_ADDRESS, abi.encode(index));
        return abi.decode(result, (uint64));
    }

    function l1BlockNumber() internal returns (uint64) {

        if (isOfflineMode()) {
            return PrecompileLib.l1BlockNumber();
        }

        bytes memory result = _makeRpcCall(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, abi.encode());
        return abi.decode(result, (uint64));
    }

    function perpAssetInfo(uint32 perp) internal returns (PrecompileLib.PerpAssetInfo memory) {

        if (isOfflineMode()) {
            return PrecompileLib.perpAssetInfo(perp);
        }

        bytes memory result = _makeRpcCall(PERP_ASSET_INFO_PRECOMPILE_ADDRESS, abi.encode(perp));
        return abi.decode(result, (PrecompileLib.PerpAssetInfo));
    }

    function spotInfo(uint32 spot) internal returns (PrecompileLib.SpotInfo memory) {

        if (isOfflineMode()) {
            return PrecompileLib.spotInfo(spot);
        }

        bytes memory result = _makeRpcCall(SPOT_INFO_PRECOMPILE_ADDRESS, abi.encode(spot));
        return abi.decode(result, (PrecompileLib.SpotInfo));
    }

    function tokenInfo(uint32 token) internal returns (PrecompileLib.TokenInfo memory) {

        if (isOfflineMode()) {
            return PrecompileLib.tokenInfo(token);
        }

        bytes memory result = _makeRpcCall(TOKEN_INFO_PRECOMPILE_ADDRESS, abi.encode(token));
        if (result.length == 0) {
            return PrecompileLib.TokenInfo({
                name: "",
                spots: new uint64[](0),
                deployerTradingFeeShare: 0,
                deployer: INVALID_ADDRESS,
                evmContract: INVALID_ADDRESS,
                szDecimals: 0,
                weiDecimals: 0,
                evmExtraWeiDecimals: 0
            });
        }
        return abi.decode(result, (PrecompileLib.TokenInfo));
    }

    function tokenSupply(uint32 token) internal returns (PrecompileLib.TokenSupply memory) {

        if (isOfflineMode()) {
            return PrecompileLib.tokenSupply(token);
        }

        bytes memory result = _makeRpcCall(TOKEN_SUPPLY_PRECOMPILE_ADDRESS, abi.encode(token));
        return abi.decode(result, (PrecompileLib.TokenSupply));
    }

    function bbo(uint32 asset) internal returns (PrecompileLib.Bbo memory) {

        if (isOfflineMode()) {
            return PrecompileLib.bbo(asset);
        }

        bytes memory result = _makeRpcCall(BBO_PRECOMPILE_ADDRESS, abi.encode(asset));
        return abi.decode(result, (PrecompileLib.Bbo));
    }

    function accountMarginSummary(uint32 perp_dex_index, address user)
        internal
        returns (PrecompileLib.AccountMarginSummary memory)
    {

        if (isOfflineMode()) {
            return PrecompileLib.accountMarginSummary(perp_dex_index, user);
        }

        bytes memory result = _makeRpcCall(ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, abi.encode(perp_dex_index, user));
        return abi.decode(result, (PrecompileLib.AccountMarginSummary));
    }

    function coreUserExists(address user) internal returns (bool) {

        if (isOfflineMode()) {
            return PrecompileLib.coreUserExists(user);
        }

        bytes memory result = _makeRpcCall(CORE_USER_EXISTS_PRECOMPILE_ADDRESS, abi.encode(user));
        return abi.decode(result, (bool));
    }
}
