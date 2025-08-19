// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

contract L1Read {
    struct Position {
        int64 szi;
        uint64 entryNtl;
        int64 isolatedRawUsd;
        uint32 leverage;
        bool isIsolated;
    }

    struct SpotBalance {
        uint64 total;
        uint64 hold;
        uint64 entryNtl;
    }

    struct UserVaultEquity {
        uint64 equity;
        uint64 lockedUntilTimestamp;
    }

    struct Withdrawable {
        uint64 withdrawable;
    }

    struct Delegation {
        address validator;
        uint64 amount;
        uint64 lockedUntilTimestamp;
    }

    struct DelegatorSummary {
        uint64 delegated;
        uint64 undelegated;
        uint64 totalPendingWithdrawal;
        uint64 nPendingWithdrawals;
    }

    struct PerpAssetInfo {
        string coin;
        uint32 marginTableId;
        uint8 szDecimals;
        uint8 maxLeverage;
        bool onlyIsolated;
    }

    struct SpotInfo {
        string name;
        uint64[2] tokens;
    }

    struct TokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }

    struct UserBalance {
        address user;
        uint64 balance;
    }

    struct TokenSupply {
        uint64 maxSupply;
        uint64 totalSupply;
        uint64 circulatingSupply;
        uint64 futureEmissions;
        UserBalance[] nonCirculatingUserBalances;
    }

    struct Bbo {
        uint64 bid;
        uint64 ask;
    }

    struct AccountMarginSummary {
        int64 accountValue;
        uint64 marginUsed;
        uint64 ntlPos;
        int64 rawUsd;
    }

    struct CoreUserExists {
        bool exists;
    }

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

    function _makeRpcCall(address target, bytes memory params) internal returns (bytes memory) {
        // Construct the JSON-RPC payload
        string memory jsonPayload =
            string.concat('[{"to":"', vm.toString(target), '","data":"', vm.toString(params), '"},"latest"]');

        // Make the RPC call
        return vm.rpc("eth_call", jsonPayload);
    }

    function position(address user, uint16 perp) external returns (Position memory) {
        bytes memory result = _makeRpcCall(POSITION_PRECOMPILE_ADDRESS, abi.encode(user, perp));
        return abi.decode(result, (Position));
    }

    function spotBalance(address user, uint64 token) external returns (SpotBalance memory) {
        bytes memory result = _makeRpcCall(SPOT_BALANCE_PRECOMPILE_ADDRESS, abi.encode(user, token));
        return abi.decode(result, (SpotBalance));
    }

    function userVaultEquity(address user, address vault) external returns (UserVaultEquity memory) {
        bytes memory result = _makeRpcCall(VAULT_EQUITY_PRECOMPILE_ADDRESS, abi.encode(user, vault));
        return abi.decode(result, (UserVaultEquity));
    }

    function withdrawable(address user) external returns (Withdrawable memory) {
        bytes memory result = _makeRpcCall(WITHDRAWABLE_PRECOMPILE_ADDRESS, abi.encode(user));
        return abi.decode(result, (Withdrawable));
    }

    function delegations(address user) external returns (Delegation[] memory) {
        bytes memory result = _makeRpcCall(DELEGATIONS_PRECOMPILE_ADDRESS, abi.encode(user));
        return abi.decode(result, (Delegation[]));
    }

    function delegatorSummary(address user) external returns (DelegatorSummary memory) {
        bytes memory result = _makeRpcCall(DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS, abi.encode(user));
        return abi.decode(result, (DelegatorSummary));
    }

    function markPx(uint32 index) external returns (uint64) {
        bytes memory result = _makeRpcCall(MARK_PX_PRECOMPILE_ADDRESS, abi.encode(index));
        return abi.decode(result, (uint64));
    }

    function oraclePx(uint32 index) external returns (uint64) {
        bytes memory result = _makeRpcCall(ORACLE_PX_PRECOMPILE_ADDRESS, abi.encode(index));
        return abi.decode(result, (uint64));
    }

    function spotPx(uint32 index) external returns (uint64) {
        bytes memory result = _makeRpcCall(SPOT_PX_PRECOMPILE_ADDRESS, abi.encode(index));
        return abi.decode(result, (uint64));
    }

    function l1BlockNumber() external returns (uint64) {
        bytes memory result = _makeRpcCall(L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS, abi.encode());
        return abi.decode(result, (uint64));
    }

    function perpAssetInfo(uint32 perp) external returns (PerpAssetInfo memory) {
        bytes memory result = _makeRpcCall(PERP_ASSET_INFO_PRECOMPILE_ADDRESS, abi.encode(perp));
        return abi.decode(result, (PerpAssetInfo));
    }

    function spotInfo(uint32 spot) external returns (SpotInfo memory) {
        bytes memory result = _makeRpcCall(SPOT_INFO_PRECOMPILE_ADDRESS, abi.encode(spot));
        return abi.decode(result, (SpotInfo));
    }

    function tokenInfo(uint32 token) external returns (TokenInfo memory) {
        bytes memory result = _makeRpcCall(TOKEN_INFO_PRECOMPILE_ADDRESS, abi.encode(token));
        return abi.decode(result, (TokenInfo));
    }

    function tokenSupply(uint32 token) external returns (TokenSupply memory) {
        bytes memory result = _makeRpcCall(TOKEN_SUPPLY_PRECOMPILE_ADDRESS, abi.encode(token));
        return abi.decode(result, (TokenSupply));
    }

    function bbo(uint32 asset) external returns (Bbo memory) {
        bytes memory result = _makeRpcCall(BBO_PRECOMPILE_ADDRESS, abi.encode(asset));
        return abi.decode(result, (Bbo));
    }

    function accountMarginSummary(uint32 perp_dex_index, address user) external returns (AccountMarginSummary memory) {
        bytes memory result = _makeRpcCall(ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS, abi.encode(perp_dex_index, user));
        return abi.decode(result, (AccountMarginSummary));
    }

    function coreUserExists(address user) external returns (CoreUserExists memory) {
        bytes memory result = _makeRpcCall(CORE_USER_EXISTS_PRECOMPILE_ADDRESS, abi.encode(user));
        return abi.decode(result, (CoreUserExists));
    }
}
