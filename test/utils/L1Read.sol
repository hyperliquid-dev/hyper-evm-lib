// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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

  address constant POSITION_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000800;
  address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
  address constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
  address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;
  address constant DELEGATIONS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000804;
  address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS =
    0x0000000000000000000000000000000000000805;
  address constant MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;
  address constant ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
  address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
  address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;
  address constant PERP_ASSET_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080a;
  address constant SPOT_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080b;
  address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
  address constant TOKEN_SUPPLY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080D;
  address constant BBO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080e;
  address constant ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS =
    0x000000000000000000000000000000000000080F;
  address constant CORE_USER_EXISTS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000810;

  function position(address user, uint16 perp) external view returns (Position memory) {
    bool success;
    bytes memory result;
    (success, result) = POSITION_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, perp));
    require(success, "Position precompile call failed");
    return abi.decode(result, (Position));
  }

  function spotBalance(address user, uint64 token) external view returns (SpotBalance memory) {
    bool success;
    bytes memory result;
    (success, result) = SPOT_BALANCE_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, token));
    require(success, "SpotBalance precompile call failed");
    return abi.decode(result, (SpotBalance));
  }

  function userVaultEquity(
    address user,
    address vault
  ) external view returns (UserVaultEquity memory) {
    bool success;
    bytes memory result;
    (success, result) = VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, vault));
    require(success, "VaultEquity precompile call failed");
    return abi.decode(result, (UserVaultEquity));
  }

  function withdrawable(address user) external view returns (Withdrawable memory) {
    bool success;
    bytes memory result;
    (success, result) = WITHDRAWABLE_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
    require(success, "Withdrawable precompile call failed");
    return abi.decode(result, (Withdrawable));
  }

  function delegations(address user) external view returns (Delegation[] memory) {
    bool success;
    bytes memory result;
    (success, result) = DELEGATIONS_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
    require(success, "Delegations precompile call failed");
    return abi.decode(result, (Delegation[]));
  }

  function delegatorSummary(address user) external view returns (DelegatorSummary memory) {
    bool success;
    bytes memory result;
    (success, result) = DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
    require(success, "DelegatorySummary precompile call failed");
    return abi.decode(result, (DelegatorSummary));
  }

  function markPx(uint32 index) external view returns (uint64) {
    bool success;
    bytes memory result;
    (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
    require(success, "MarkPx precompile call failed");
    return abi.decode(result, (uint64));
  }

  function oraclePx(uint32 index) external view returns (uint64) {
    bool success;
    bytes memory result;
    (success, result) = ORACLE_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
    require(success, "OraclePx precompile call failed");
    return abi.decode(result, (uint64));
  }

  function spotPx(uint32 index) external view returns (uint64) {
    bool success;
    bytes memory result;
    (success, result) = SPOT_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
    require(success, "SpotPx precompile call failed");
    return abi.decode(result, (uint64));
  }

  function l1BlockNumber() external view returns (uint64) {
    bool success;
    bytes memory result;
    (success, result) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
    require(success, "L1BlockNumber precompile call failed");
    return abi.decode(result, (uint64));
  }

  function perpAssetInfo(uint32 perp) external view returns (PerpAssetInfo memory) {
    bool success;
    bytes memory result;
    (success, result) = PERP_ASSET_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(perp));
    require(success, "PerpAssetInfo precompile call failed");
    return abi.decode(result, (PerpAssetInfo));
  }

  function spotInfo(uint32 spot) external view returns (SpotInfo memory) {
    bool success;
    bytes memory result;
    (success, result) = SPOT_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(spot));
    require(success, "SpotInfo precompile call failed");
    return abi.decode(result, (SpotInfo));
  }

  function tokenInfo(uint32 token) external view returns (TokenInfo memory) {
    bool success;
    bytes memory result;
    (success, result) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
    require(success, "TokenInfo precompile call failed");
    return abi.decode(result, (TokenInfo));
  }

  function tokenSupply(uint32 token) external view returns (TokenSupply memory) {
    bool success;
    bytes memory result;
    (success, result) = TOKEN_SUPPLY_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
    require(success, "TokenSupply precompile call failed");
    return abi.decode(result, (TokenSupply));
  }

  function bbo(uint32 asset) external view returns (Bbo memory) {
    bool success;
    bytes memory result;
    (success, result) = BBO_PRECOMPILE_ADDRESS.staticcall(abi.encode(asset));
    require(success, "Bbo precompile call failed");
    return abi.decode(result, (Bbo));
  }

  function accountMarginSummary(
    uint32 perp_dex_index,
    address user
  ) external view returns (AccountMarginSummary memory) {
    bool success;
    bytes memory result;
    (success, result) = ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS.staticcall(
      abi.encode(perp_dex_index, user)
    );
    require(success, "Account margin summary precompile call failed");
    return abi.decode(result, (AccountMarginSummary));
  }

  function coreUserExists(address user) external view returns (CoreUserExists memory) {
    bool success;
    bytes memory result;
    (success, result) = CORE_USER_EXISTS_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
    require(success, "Core user exists precompile call failed");
    return abi.decode(result, (CoreUserExists));
  }
}