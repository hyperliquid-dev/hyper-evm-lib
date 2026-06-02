// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ITokenRegistry} from "./interfaces/ITokenRegistry.sol";
import {HLConstants} from "./common/HLConstants.sol";

/**
 * @title PrecompileLib v1.1
 * @author Obsidian (https://x.com/ObsidianAudits)
 * @notice A library with helper functions for interacting with HyperEVM's precompiles
 *
 * @dev Each precompile query has two variants:
 *  - Reverting (e.g. `position`): reverts with a typed error on precompile failure.
 *  - Non-reverting (e.g. `tryPosition`): returns `(result, bool success)`. On
 *    failure `result` is zero-initialized.
 *
 * @dev Precompile gas cost formula: 2000 + 65 * (input_len + output_len). Each
 *  fixed-output reader caps its staticcall at the matching `HLConstants.*_GAS`
 *  constant (~20% above the formula) to prevent runaway gas burn when a precompile
 *  reverts or is unavailable. Dynamic-output readers (`delegations`, `perpAssetInfo`,
 *  `spotInfo`, `tokenInfo`, `tokenSupply`) cannot be bounded statically because
 *  their return size depends on chain state. Each dynamic-output reader exposes a
 *  `(args, uint256 gas)` overload so callers can pass an explicit cap; the default
 *  no-cap overload forwards `gasleft()` (i.e. all remaining gas, subject to the
 *  EVM's 63/64 rule).
 */
library PrecompileLib {
    // Onchain record of token indices for each linked evm contract
    ITokenRegistry constant REGISTRY = ITokenRegistry(0x0b51d1A9098cf8a72C325003F44C194D41d7A85B);

    /*//////////////////////////////////////////////////////////////
                  Custom Utility Functions
        (Overloads accepting token address instead of index)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets TokenInfo for a given token address by looking up its index and fetching from the precompile.
     * @dev Overload of tokenInfo(uint64 token)
     */
    function tokenInfo(address tokenAddress) internal view returns (TokenInfo memory) {
        uint64 index = getTokenIndex(tokenAddress);
        return tokenInfo(index);
    }

    /**
     * @notice Gets SpotInfo for the token/USDC market using the token address.
     * @dev Overload of spotInfo(uint64 tokenIndex)
     * Finds the spot market where USDC (index 0) is the quote.
     */
    function spotInfo(address tokenAddress) internal view returns (SpotInfo memory) {
        uint64 tokenIndex = getTokenIndex(tokenAddress);
        uint64 spotIndex = getSpotIndex(tokenIndex);
        return spotInfo(spotIndex);
    }

    /**
     * @notice Gets the spot price for the token/USDC market using the token address.
     * @dev Overload of spotPx(uint64 spotIndex)
     */
    function spotPx(address tokenAddress) internal view returns (uint64) {
        uint64 tokenIndex = getTokenIndex(tokenAddress);
        uint64 spotIndex = getSpotIndex(tokenIndex);
        return spotPx(spotIndex);
    }

    /**
     * @notice Gets a user's spot balance for a given token address.
     * @dev Overload of spotBalance(address user, uint64 token)
     */
    function spotBalance(address user, address tokenAddress) internal view returns (SpotBalance memory) {
        uint64 tokenIndex = getTokenIndex(tokenAddress);
        return spotBalance(user, tokenIndex);
    }

    /**
     * @notice Gets the index of a token from its address. Reverts if token is not linked to HyperCore.
     */
    function getTokenIndex(address tokenAddress) internal view returns (uint64) {
        if (tokenAddress == HLConstants.usdc()) {
            return HLConstants.USDC_TOKEN_INDEX;
        }
        return REGISTRY.getTokenIndex(tokenAddress);
    }

    /**
     * @notice Gets the spot market index for the token/USDC pair for a token using its address.
     * @dev Overload of getSpotIndex(uint64 tokenIndex)
     */
    function getSpotIndex(address tokenAddress) internal view returns (uint64) {
        uint64 tokenIndex = getTokenIndex(tokenAddress);
        return getSpotIndex(tokenIndex);
    }

    /**
     * @notice Gets the spot market index for a token.
     * @dev If only one spot market exists, returns it. Otherwise, finds the spot market with USDC as the quote token.
     */
    function getSpotIndex(uint64 tokenIndex) internal view returns (uint64) {
        uint64[] memory spots = tokenInfo(tokenIndex).spots;

        if (spots.length == 1) return spots[0];

        for (uint256 idx = 0; idx < spots.length; idx++) {
            SpotInfo memory spot = spotInfo(spots[idx]);
            if (spot.tokens[1] == 0) {
                // index 0 = USDC
                return spots[idx];
            }
        }
        revert PrecompileLib__SpotIndexNotFound();
    }

    /*//////////////////////////////////////////////////////////////
                  Using Alternate Quote Token (non USDC)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the spot market index for a token/quote pair.
     * Iterates all spot markets for the token and matches the quote token index.
     * @dev Overload of getSpotIndex(uint64 tokenIndex)
     */
    function getSpotIndex(uint64 tokenIndex, uint64 quoteTokenIndex) internal view returns (uint64) {
        uint64[] memory spots = tokenInfo(tokenIndex).spots;

        for (uint256 idx = 0; idx < spots.length; idx++) {
            SpotInfo memory spot = spotInfo(spots[idx]);
            if (spot.tokens[1] == quoteTokenIndex) {
                return spots[idx];
            }
        }
        revert PrecompileLib__SpotIndexNotFound();
    }

    /**
     * @notice Gets SpotInfo for a token/quote pair using token addresses.
     * Looks up both token and quote indices, then finds the spot market.
     * @dev Overload of spotInfo(uint64 spotIndex)
     */
    function spotInfo(address token, address quoteToken) internal view returns (SpotInfo memory) {
        uint64 tokenIndex = getTokenIndex(token);
        uint64 quoteTokenIndex = getTokenIndex(quoteToken);
        uint64 spotIndex = getSpotIndex(tokenIndex, quoteTokenIndex);
        return spotInfo(spotIndex);
    }

    /**
     * @notice Gets the spot price for a token/quote pair using token addresses.
     * Looks up both token and quote indices, then finds the spot market.
     * @dev Overload of spotPx(uint64 spotIndex)
     */
    function spotPx(address token, address quoteToken) internal view returns (uint64) {
        uint64 tokenIndex = getTokenIndex(token);
        uint64 quoteTokenIndex = getTokenIndex(quoteToken);
        uint64 spotIndex = getSpotIndex(tokenIndex, quoteTokenIndex);
        return spotPx(spotIndex);
    }

    /*//////////////////////////////////////////////////////////////
                        Price decimals normalization
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the spot price for `spotIndex` normalized to a uint256 fixed-point with
     *  8 decimals (regardless of the underlying token's szDecimals).
     * @dev Hyperliquid stores spot px with `8 - baseSzDecimals` decimals; this scales up by
     *  `10**baseSzDecimals` so all spot prices share a single decimal convention.
     */
    function normalizedSpotPx(uint64 spotIndex) internal view returns (uint256) {
        SpotInfo memory info = spotInfo(spotIndex);
        uint8 baseSzDecimals = tokenInfo(info.tokens[0]).szDecimals;
        return spotPx(spotIndex) * 10 ** baseSzDecimals;
    }

    /**
     * @notice Returns the mark price for `perpIndex` normalized to a uint256 fixed-point with
     *  6 decimals.
     * @dev Hyperliquid stores perp px with `6 - szDecimals` decimals; this scales up by
     *  `10**szDecimals` so all perp mark prices share a single decimal convention.
     */
    function normalizedMarkPx(uint32 perpIndex) internal view returns (uint256) {
        PerpAssetInfo memory info = perpAssetInfo(perpIndex);
        return markPx(perpIndex) * 10 ** info.szDecimals;
    }

    /**
     * @notice Returns the perp oracle (index) price for `perpIndex` normalized to a uint256
     *  fixed-point with 6 decimals. See `normalizedMarkPx` for scaling notes.
     */
    function normalizedOraclePx(uint32 perpIndex) internal view returns (uint256) {
        PerpAssetInfo memory info = perpAssetInfo(perpIndex);
        return oraclePx(perpIndex) * 10 ** info.szDecimals;
    }

    /*//////////////////////////////////////////////////////////////
                              Precompile Calls
    //////////////////////////////////////////////////////////////*/

    // ============ Position (uint32 perp via POSITION2 precompile) ============

    /**
     * @notice Query `user`'s perpetual position for perp `perp` (32-bit, via POSITION2 precompile).
     * @dev Supports the extended HIP-3 perp index range (uint32). Reverts on precompile failure.
     *  Returns `Position { szi, entryNtl, isolatedRawUsd, leverage, isIsolated }`:
     *  - `szi`: signed position size in base token wei (positive = long, negative = short, 0 = none).
     *  - `entryNtl`: cumulative entry notional in USDC wei.
     *  - `isolatedRawUsd`: isolated-margin USDC wei (0 for cross-margin positions).
     *  - `leverage`: position leverage (uint32, per Hyperliquid scaling).
     *  - `isIsolated`: true for isolated-margin positions, false for cross.
     */
    function position(address user, uint32 perp) internal view returns (Position memory) {
        (Position memory result, bool success) = tryPosition2(user, perp);
        if (!success) revert PrecompileLib__Position2PrecompileFailed();
        return result;
    }

    /// @notice Alias for `position(address,uint32)` that matches the upstream `position2` naming.
    function position2(address user, uint32 perp) internal view returns (Position memory) {
        return position(user, perp);
    }

    /// @notice Non-reverting version of `position2`. Returns success=false on precompile failure.
    function tryPosition2(address user, uint32 perp) internal view returns (Position memory result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.POSITION2_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.POSITION_GAS}(abi.encode(user, perp));
        if (!_success) return (result, false);
        return (abi.decode(_result, (Position)), true);
    }

    // ============ Position (uint16 perp via POSITION precompile) ============

    /**
     * @notice Query `user`'s perpetual position via the legacy POSITION precompile at 0x800
     *  (16-bit perp index).
     * @dev Functionally superseded by `position` / `position2` (POSITION2 at 0x813), which
     *  supports the wider HIP-3 perp index range. Exposed here for direct legacy access; new
     *  code should prefer `position(address,uint32)`. Distinct name avoids overload ambiguity.
     *  See `position` for return field semantics.
     */
    function positionLegacy(address user, uint16 perp) internal view returns (Position memory) {
        (Position memory result, bool success) = tryPositionLegacy(user, perp);
        if (!success) revert PrecompileLib__PositionPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `positionLegacy`.
    function tryPositionLegacy(address user, uint16 perp) internal view returns (Position memory result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.POSITION_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.POSITION_GAS}(abi.encode(user, perp));
        if (!_success) return (result, false);
        return (abi.decode(_result, (Position)), true);
    }

    // ============ Spot Balance ============

    /**
     * @notice Query `user`'s Core spot balance for a token (by Core token index).
     * @param user EVM address.
     * @param token Core token index (use `HLConstants.USDC_TOKEN_INDEX` for USDC,
     *  `HLConstants.hypeTokenIndex()` for HYPE).
     * @dev Returns `SpotBalance { total, hold, entryNtl }`, all in Core wei
     *  (token's `weiDecimals`):
     *  - `total`: total spot balance (includes amount locked in open orders / holds).
     *  - `hold`: portion locked in open orders or pending transfers; spendable = `total - hold`.
     *  - `entryNtl`: cumulative entry notional in USDC wei (used for PnL/funding accounting).
     *  Address overload `spotBalance(address user, address tokenAddress)` resolves token
     *  index automatically.
     */
    function spotBalance(address user, uint64 token) internal view returns (SpotBalance memory) {
        (SpotBalance memory result, bool success) = trySpotBalance(user, token);
        if (!success) revert PrecompileLib__SpotBalancePrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `spotBalance`. Returns zero-initialized struct on failure.
    function trySpotBalance(address user, uint64 token)
        internal
        view
        returns (SpotBalance memory result, bool success)
    {
        (bool _success, bytes memory _result) = HLConstants.SPOT_BALANCE_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.SPOT_BALANCE_GAS}(
            abi.encode(user, token)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (SpotBalance)), true);
    }

    // ============ User Vault Equity ============

    /**
     * @notice Query `user`'s equity in a Hyperliquid vault.
     * @param user EVM address of the depositor.
     * @param vault Vault address on Core (Hyperliquid vault identifier).
     * @dev Returns `UserVaultEquity { equity, lockedUntilTimestamp }`:
     *  - `equity`: depositor's vault equity in USDC wei (6 decimals).
     *  - `lockedUntilTimestamp`: unix seconds until which the deposit is locked. Hyperliquid
     *    vaults enforce a minimum lockup (e.g. ~1 hour for HLP); withdrawals before this
     *    timestamp are rejected by Core.
     */
    function userVaultEquity(address user, address vault) internal view returns (UserVaultEquity memory) {
        (UserVaultEquity memory result, bool success) = tryUserVaultEquity(user, vault);
        if (!success) revert PrecompileLib__VaultEquityPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `userVaultEquity`. Returns zero-initialized struct on failure.
    function tryUserVaultEquity(address user, address vault)
        internal
        view
        returns (UserVaultEquity memory result, bool success)
    {
        (bool _success, bytes memory _result) = HLConstants.VAULT_EQUITY_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.VAULT_EQUITY_GAS}(
            abi.encode(user, vault)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (UserVaultEquity)), true);
    }

    // ============ Withdrawable ============

    /**
     * @notice Query the amount of USDC `user` can withdraw from their Core perp account.
     * @dev Returned in USDC wei (6 decimals). This is the perp account's free balance
     *  (account value minus margin obligations); not the spot USDC balance. To move funds
     *  between perp and spot accounts on Core use `usdClassTransfer`; spot-to-EVM moves
     *  use `spotSend` to the system address.
     */
    function withdrawable(address user) internal view returns (uint64) {
        (uint64 result, bool success) = tryWithdrawable(user);
        if (!success) revert PrecompileLib__WithdrawablePrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `withdrawable`. Returns 0 on failure.
    function tryWithdrawable(address user) internal view returns (uint64 result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.WITHDRAWABLE_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.WITHDRAWABLE_GAS}(abi.encode(user));
        if (!_success) return (0, false);
        return (abi.decode(_result, (Withdrawable)).withdrawable, true);
    }

    // ============ Delegations (dynamic output, uncapped) ============

    /**
     * @notice Query `user`'s active staking delegations.
     * @dev Returns an array of `Delegation { validator, amount, lockedUntilTimestamp }`:
     *  - `validator`: validator EVM address receiving the delegation.
     *  - `amount`: delegated HYPE in Core wei (8 decimals; multiply by 1e10 for EVM 18-dec).
     *  - `lockedUntilTimestamp`: unix seconds until the delegation can be undelegated
     *    (Hyperliquid enforces a 1-day lockup after each `tokenDelegate`).
     *  Undelegated stake in the ~7-day unbonding queue is not included here; see
     *  `delegatorSummary` for aggregate pending-withdrawal totals. Output length is
     *  dynamic — this precompile is not gas-capped.
     */
    function delegations(address user) internal view returns (Delegation[] memory) {
        return delegations(user, gasleft());
    }

    /// @notice Gas-capped overload. `gas` bounds the precompile staticcall.
    function delegations(address user, uint256 gas) internal view returns (Delegation[] memory) {
        (Delegation[] memory result, bool success) = tryDelegations(user, gas);
        if (!success) revert PrecompileLib__DelegationsPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `delegations`. Returns empty array on failure.
    function tryDelegations(address user) internal view returns (Delegation[] memory result, bool success) {
        return tryDelegations(user, gasleft());
    }

    /// @notice Gas-capped overload of `tryDelegations`. `gas` bounds the precompile staticcall.
    function tryDelegations(address user, uint256 gas)
        internal
        view
        returns (Delegation[] memory result, bool success)
    {
        (bool _success, bytes memory _result) = HLConstants.DELEGATIONS_PRECOMPILE_ADDRESS.staticcall{gas: gas}(
            abi.encode(user)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (Delegation[])), true);
    }

    // ============ Delegator Summary ============

    /**
     * @notice Query aggregate staking state for `user`.
     * @dev Returns `DelegatorSummary { delegated, undelegated, totalPendingWithdrawal,
     *  nPendingWithdrawals }`, all HYPE amounts in Core wei (8 decimals):
     *  - `delegated`: total HYPE actively delegated to validators.
     *  - `undelegated`: HYPE on the staking balance ready to be re-delegated or withdrawn
     *    via `stakingWithdraw` (i.e. moved back to Core spot).
     *  - `totalPendingWithdrawal`: HYPE in the ~7-day unbonding queue (not yet on staking balance).
     *  - `nPendingWithdrawals`: number of distinct pending unbond entries.
     */
    function delegatorSummary(address user) internal view returns (DelegatorSummary memory) {
        (DelegatorSummary memory result, bool success) = tryDelegatorSummary(user);
        if (!success) revert PrecompileLib__DelegatorSummaryPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `delegatorSummary`. Returns zero-initialized struct on failure.
    function tryDelegatorSummary(address user) internal view returns (DelegatorSummary memory result, bool success) {
        (bool _success, bytes memory _result) = HLConstants.DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.DELEGATOR_SUMMARY_GAS}(
            abi.encode(user)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (DelegatorSummary)), true);
    }

    // ============ Mark Price ============

    /**
     * @notice Query the current mark price for perp `perpIndex`.
     * @dev Mark price is derived from recent fills + spot reference; used for PnL / liquidation
     *  display. Returned as a uint64 fixed-point with `6 - szDecimals` decimal places (per
     *  Hyperliquid perp price scaling). Use `normalizedMarkPx` to get a 6-decimal value.
     */
    function markPx(uint32 perpIndex) internal view returns (uint64) {
        (uint64 result, bool success) = tryMarkPx(perpIndex);
        if (!success) revert PrecompileLib__MarkPxPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `markPx`. Returns 0 on failure.
    function tryMarkPx(uint32 perpIndex) internal view returns (uint64 result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.MARK_PX_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.MARK_PX_GAS}(abi.encode(perpIndex));
        if (!_success) return (0, false);
        return (abi.decode(_result, (uint64)), true);
    }

    // ============ Oracle Price ============

    /**
     * @notice Query the current oracle (index) price for perp `perpIndex`.
     * @dev Oracle price feeds funding-rate and margin computations; differs from mark price
     *  (which is fill-driven). Returned as a uint64 fixed-point with `6 - szDecimals` decimals.
     *  Use `normalizedOraclePx` to get a 6-decimal value.
     */
    function oraclePx(uint32 perpIndex) internal view returns (uint64) {
        (uint64 result, bool success) = tryOraclePx(perpIndex);
        if (!success) revert PrecompileLib__OraclePxPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `oraclePx`. Returns 0 on failure.
    function tryOraclePx(uint32 perpIndex) internal view returns (uint64 result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.ORACLE_PX_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.ORACLE_PX_GAS}(abi.encode(perpIndex));
        if (!_success) return (0, false);
        return (abi.decode(_result, (uint64)), true);
    }

    // ============ Spot Price ============

    /**
     * @notice Query the current spot price for spot market `spotIndex`.
     * @dev Returned as a uint64 fixed-point with `8 - baseSzDecimals` decimals (per Hyperliquid
     *  spot price scaling, denominated in the quote token). Use `normalizedSpotPx` to get an
     *  8-decimal value, or the address overload `spotPx(address tokenAddress)` to look up
     *  by EVM token (resolves to the token/USDC market).
     */
    function spotPx(uint64 spotIndex) internal view returns (uint64) {
        (uint64 result, bool success) = trySpotPx(spotIndex);
        if (!success) revert PrecompileLib__SpotPxPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `spotPx`. Returns 0 on failure.
    function trySpotPx(uint64 spotIndex) internal view returns (uint64 result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.SPOT_PX_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.SPOT_PX_GAS}(abi.encode(spotIndex));
        if (!_success) return (0, false);
        return (abi.decode(_result, (uint64)), true);
    }

    // ============ Perp Asset Info (dynamic output, uncapped) ============

    /**
     * @notice Query static metadata for perp asset `perp`.
     * @dev Returns `PerpAssetInfo { coin, marginTableId, szDecimals, maxLeverage, onlyIsolated }`:
     *  - `coin`: ticker (e.g. "BTC").
     *  - `marginTableId`: ID of the margin schedule (initial/maintenance margin tiers) used
     *    for this perp.
     *  - `szDecimals`: decimal count for trade size; perp prices use `6 - szDecimals` decimals.
     *  - `maxLeverage`: maximum supported leverage.
     *  - `onlyIsolated`: if true, the perp supports only isolated margin (not cross).
     *  Output is dynamic length (string field) — this precompile is not gas-capped.
     */
    function perpAssetInfo(uint32 perp) internal view returns (PerpAssetInfo memory) {
        return perpAssetInfo(perp, gasleft());
    }

    /// @notice Gas-capped overload. `gas` bounds the precompile staticcall.
    function perpAssetInfo(uint32 perp, uint256 gas) internal view returns (PerpAssetInfo memory) {
        (PerpAssetInfo memory result, bool success) = tryPerpAssetInfo(perp, gas);
        if (!success) revert PrecompileLib__PerpAssetInfoPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `perpAssetInfo`. Returns zero-initialized struct on failure.
    function tryPerpAssetInfo(uint32 perp) internal view returns (PerpAssetInfo memory result, bool success) {
        return tryPerpAssetInfo(perp, gasleft());
    }

    /// @notice Gas-capped overload of `tryPerpAssetInfo`. `gas` bounds the precompile staticcall.
    function tryPerpAssetInfo(uint32 perp, uint256 gas)
        internal
        view
        returns (PerpAssetInfo memory result, bool success)
    {
        (bool _success, bytes memory _result) =
            HLConstants.PERP_ASSET_INFO_PRECOMPILE_ADDRESS.staticcall{gas: gas}(abi.encode(perp));
        if (!_success) return (result, false);
        return (abi.decode(_result, (PerpAssetInfo)), true);
    }

    // ============ Spot Info (dynamic output, uncapped) ============

    /**
     * @notice Query static metadata for spot market `spotIndex`.
     * @dev Returns `SpotInfo { name, tokens }` where `tokens` is `[baseTokenIndex, quoteTokenIndex]`.
     *  For most markets, `tokens[1]` is the USDC token index (0). Address overloads
     *  `spotInfo(address tokenAddress)` and `spotInfo(address token, address quoteToken)`
     *  resolve indices automatically. Output is dynamic length — not gas-capped.
     */
    function spotInfo(uint64 spotIndex) internal view returns (SpotInfo memory) {
        return spotInfo(spotIndex, gasleft());
    }

    /// @notice Gas-capped overload. `gas` bounds the precompile staticcall.
    function spotInfo(uint64 spotIndex, uint256 gas) internal view returns (SpotInfo memory) {
        (SpotInfo memory result, bool success) = trySpotInfo(spotIndex, gas);
        if (!success) revert PrecompileLib__SpotInfoPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `spotInfo`. Returns zero-initialized struct on failure.
    function trySpotInfo(uint64 spotIndex) internal view returns (SpotInfo memory result, bool success) {
        return trySpotInfo(spotIndex, gasleft());
    }

    /// @notice Gas-capped overload of `trySpotInfo`. `gas` bounds the precompile staticcall.
    function trySpotInfo(uint64 spotIndex, uint256 gas) internal view returns (SpotInfo memory result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.SPOT_INFO_PRECOMPILE_ADDRESS.staticcall{gas: gas}(abi.encode(spotIndex));
        if (!_success) return (result, false);
        return (abi.decode(_result, (SpotInfo)), true);
    }

    // ============ Token Info (dynamic output, uncapped) ============

    /**
     * @notice Query static metadata for a Core token by index.
     * @dev Returns `TokenInfo { name, spots, deployerTradingFeeShare, deployer, evmContract,
     *  szDecimals, weiDecimals, evmExtraWeiDecimals }`:
     *  - `name`: ticker (e.g. "USDC", "HYPE").
     *  - `spots`: array of spot market indices in which this token participates.
     *  - `deployerTradingFeeShare`: portion of trading fees routed to the deployer (bps-scaled).
     *  - `deployer`: token deployer EVM address.
     *  - `evmContract`: linked ERC20 address on EVM (zero if not bridged to EVM).
     *  - `szDecimals`: trade size decimal count.
     *  - `weiDecimals`: Core-side wei decimal count.
     *  - `evmExtraWeiDecimals`: signed delta — EVM contract decimals = `weiDecimals + evmExtraWeiDecimals`.
     *    HYPE on EVM is 18 decimals while Core uses 8 (evmExtraWeiDecimals = 10).
     *  Output is dynamic length — not gas-capped.
     */
    function tokenInfo(uint64 token) internal view returns (TokenInfo memory) {
        return tokenInfo(token, gasleft());
    }

    /// @notice Gas-capped overload. `gas` bounds the precompile staticcall.
    function tokenInfo(uint64 token, uint256 gas) internal view returns (TokenInfo memory) {
        (TokenInfo memory result, bool success) = tryTokenInfo(token, gas);
        if (!success) revert PrecompileLib__TokenInfoPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `tokenInfo`. Returns zero-initialized struct on failure.
    function tryTokenInfo(uint64 token) internal view returns (TokenInfo memory result, bool success) {
        return tryTokenInfo(token, gasleft());
    }

    /// @notice Gas-capped overload of `tryTokenInfo`. `gas` bounds the precompile staticcall.
    function tryTokenInfo(uint64 token, uint256 gas) internal view returns (TokenInfo memory result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall{gas: gas}(abi.encode(token));
        if (!_success) return (result, false);
        return (abi.decode(_result, (TokenInfo)), true);
    }

    // ============ Token Supply (dynamic output, uncapped) ============

    /**
     * @notice Query supply metrics for a Core token.
     * @dev Returns `TokenSupply { maxSupply, totalSupply, circulatingSupply, futureEmissions,
     *  nonCirculatingUserBalances }`, supplies in Core wei (token's `weiDecimals`).
     *  `nonCirculatingUserBalances` lists addresses (e.g. team / treasury allocations) whose
     *  balances are excluded from circulating supply. Output is dynamic length — not gas-capped.
     */
    function tokenSupply(uint64 token) internal view returns (TokenSupply memory) {
        return tokenSupply(token, gasleft());
    }

    /// @notice Gas-capped overload. `gas` bounds the precompile staticcall.
    function tokenSupply(uint64 token, uint256 gas) internal view returns (TokenSupply memory) {
        (TokenSupply memory result, bool success) = tryTokenSupply(token, gas);
        if (!success) revert PrecompileLib__TokenSupplyPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `tokenSupply`. Returns zero-initialized struct on failure.
    function tryTokenSupply(uint64 token) internal view returns (TokenSupply memory result, bool success) {
        return tryTokenSupply(token, gasleft());
    }

    /// @notice Gas-capped overload of `tryTokenSupply`. `gas` bounds the precompile staticcall.
    function tryTokenSupply(uint64 token, uint256 gas) internal view returns (TokenSupply memory result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.TOKEN_SUPPLY_PRECOMPILE_ADDRESS.staticcall{gas: gas}(abi.encode(token));
        if (!_success) return (result, false);
        return (abi.decode(_result, (TokenSupply)), true);
    }

    // ============ L1 Block Number ============

    /**
     * @notice Query the current Hyperliquid Core (L1) block number.
     * @dev Useful for cross-referencing Core-side timing. CoreWriter actions emitted in EVM
     *  block N are typically applied on Core in the next Core block; reading `l1BlockNumber()`
     *  alongside `block.number` lets callers reason about settlement timing.
     */
    function l1BlockNumber() internal view returns (uint64) {
        (uint64 result, bool success) = tryL1BlockNumber();
        if (!success) revert PrecompileLib__L1BlockNumberPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `l1BlockNumber`. Returns 0 on failure.
    function tryL1BlockNumber() internal view returns (uint64 result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.L1_BLOCK_NUMBER_GAS}("");
        if (!_success) return (0, false);
        return (abi.decode(_result, (uint64)), true);
    }

    // ============ BBO ============

    /**
     * @notice Query best-bid / best-offer for market `asset`.
     * @param asset Spot index for spot markets, or perp index for perp markets (Hyperliquid uses
     *  a shared asset-id namespace at the precompile level).
     * @dev Returns `Bbo { bid, ask }` at the same fixed-point scaling as the respective px
     *  precompile (`spotPx` / `markPx`). Either side may be 0 when no quote exists.
     */
    function bbo(uint64 asset) internal view returns (Bbo memory) {
        (Bbo memory result, bool success) = tryBbo(asset);
        if (!success) revert PrecompileLib__BboPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `bbo`. Returns zero-initialized struct on failure.
    function tryBbo(uint64 asset) internal view returns (Bbo memory result, bool success) {
        (bool _success, bytes memory _result) =
            HLConstants.BBO_PRECOMPILE_ADDRESS.staticcall{gas: HLConstants.BBO_GAS}(abi.encode(asset));
        if (!_success) return (result, false);
        return (abi.decode(_result, (Bbo)), true);
    }

    // ============ Account Margin Summary ============

    /**
     * @notice Query margin metrics for `user`'s perp account on dex `perpDexIndex`.
     * @param perpDexIndex Perp dex selector. Use `HLConstants.DEFAULT_PERP_DEX` (0) for the
     *  main Hyperliquid perp dex; nonzero values target additional HIP-3 perp dexes.
     * @param user EVM address.
     * @dev Returns `AccountMarginSummary { accountValue, marginUsed, ntlPos, rawUsd }`, all in
     *  USDC-equivalent 6-decimal wei:
     *  - `accountValue` (signed): mark-to-market account value including unrealized PnL.
     *  - `marginUsed`: maintenance margin currently locked by open positions.
     *  - `ntlPos`: aggregate notional position size (|sum of position notionals|).
     *  - `rawUsd` (signed): non-mark-to-market USD balance.
     *  Perp and spot accounts are separate on Hyperliquid; this returns the perp side only.
     */
    function accountMarginSummary(uint32 perpDexIndex, address user)
        internal
        view
        returns (AccountMarginSummary memory)
    {
        (AccountMarginSummary memory result, bool success) = tryAccountMarginSummary(perpDexIndex, user);
        if (!success) revert PrecompileLib__AccountMarginSummaryPrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `accountMarginSummary`. Returns zero-initialized struct on failure.
    function tryAccountMarginSummary(uint32 perpDexIndex, address user)
        internal
        view
        returns (AccountMarginSummary memory result, bool success)
    {
        (bool _success, bytes memory _result) = HLConstants.ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.ACCOUNT_MARGIN_SUMMARY_GAS}(
            abi.encode(perpDexIndex, user)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (AccountMarginSummary)), true);
    }

    // ============ Core User Exists ============

    /**
     * @notice Returns whether `user` is registered on Hyperliquid Core.
     * @dev A user becomes registered on first inbound interaction (deposit, spotSend, etc.).
     *  Several CoreWriter actions targeting an unregistered recipient are silently dropped on
     *  Core (e.g. spotSend to a never-seen address can be lost). Pre-checking existence lets
     *  callers refuse to send to unregistered recipients or fall back to bridging via the
     *  system address. Always pair with off-chain confirmation for high-value transfers.
     */
    function coreUserExists(address user) internal view returns (bool) {
        (bool exists, bool success) = tryCoreUserExists(user);
        if (!success) revert PrecompileLib__CoreUserExistsPrecompileFailed();
        return exists;
    }

    /// @notice Non-reverting version of `coreUserExists`. Returns (false, false) on failure.
    function tryCoreUserExists(address user) internal view returns (bool exists, bool success) {
        (bool _success, bytes memory _result) = HLConstants.CORE_USER_EXISTS_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.CORE_USER_EXISTS_GAS}(
            abi.encode(user)
        );
        if (!_success) return (false, false);
        return (abi.decode(_result, (CoreUserExists)).exists, true);
    }

    // ============ Borrow/Lend User State ============

    /**
     * @notice Query `user`'s position in the Core borrow/lend market for `token`.
     * @dev Returns `BorrowLendUserTokenState { borrow, supply }`, each a `BasisAndValue
     *  { basis, value }`:
     *  - `borrow.value` / `supply.value`: current borrowed / supplied amount in token wei.
     *  - `borrow.basis` / `supply.basis`: stored index basis used for interest accrual delta
     *    math (interest accrues continuously between reads; current realized amount is
     *    derived by combining `value` with the current reserve index).
     *  This is the Hyperliquid protocol-level lending market — distinct from any third-party
     *  lending built atop Core.
     */
    function borrowLendUserState(address user, uint64 token) internal view returns (BorrowLendUserTokenState memory) {
        (BorrowLendUserTokenState memory result, bool success) = tryBorrowLendUserState(user, token);
        if (!success) revert PrecompileLib__BorrowLendUserStatePrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `borrowLendUserState`. Returns zero-initialized struct on failure.
    function tryBorrowLendUserState(address user, uint64 token)
        internal
        view
        returns (BorrowLendUserTokenState memory result, bool success)
    {
        (bool _success, bytes memory _result) = HLConstants.BORROW_LEND_USER_STATE_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.BORROW_LEND_USER_STATE_GAS}(
            abi.encode(user, token)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (BorrowLendUserTokenState)), true);
    }

    // ============ Borrow/Lend Reserve State ============

    /**
     * @notice Query global reserve state for the Core borrow/lend market for `token`.
     * @dev Returns `BorrowLendReserveState { borrowYearlyRateBps, supplyYearlyRateBps, balance,
     *  utilizationBps, oraclePx, ltvBps, totalSupplied, totalBorrowed }`:
     *  - `borrowYearlyRateBps` / `supplyYearlyRateBps`: current annualized rates in bps.
     *  - `balance`: free liquidity available to borrow (token wei).
     *  - `utilizationBps`: `totalBorrowed / totalSupplied` in bps.
     *  - `oraclePx`: oracle price used when valuing this token as collateral.
     *  - `ltvBps`: maximum loan-to-value when used as collateral, in bps.
     *  - `totalSupplied` / `totalBorrowed`: market-wide totals in token wei.
     */
    function borrowLendReserveState(uint64 token) internal view returns (BorrowLendReserveState memory) {
        (BorrowLendReserveState memory result, bool success) = tryBorrowLendReserveState(token);
        if (!success) revert PrecompileLib__BorrowLendReserveStatePrecompileFailed();
        return result;
    }

    /// @notice Non-reverting version of `borrowLendReserveState`. Returns zero-initialized struct on failure.
    function tryBorrowLendReserveState(uint64 token)
        internal
        view
        returns (BorrowLendReserveState memory result, bool success)
    {
        (bool _success, bytes memory _result) = HLConstants.BORROW_LEND_RESERVE_STATE_PRECOMPILE_ADDRESS
        .staticcall{gas: HLConstants.BORROW_LEND_RESERVE_STATE_GAS}(
            abi.encode(token)
        );
        if (!_success) return (result, false);
        return (abi.decode(_result, (BorrowLendReserveState)), true);
    }

    /*//////////////////////////////////////////////////////////////
                       Structs
    //////////////////////////////////////////////////////////////*/
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

    struct BasisAndValue {
        uint64 basis;
        uint64 value;
    }

    struct BorrowLendUserTokenState {
        BasisAndValue borrow;
        BasisAndValue supply;
    }

    struct BorrowLendReserveState {
        uint64 borrowYearlyRateBps;
        uint64 supplyYearlyRateBps;
        uint64 balance;
        uint64 utilizationBps;
        uint64 oraclePx;
        uint64 ltvBps;
        uint64 totalSupplied;
        uint64 totalBorrowed;
    }

    error PrecompileLib__PositionPrecompileFailed();
    error PrecompileLib__Position2PrecompileFailed();
    error PrecompileLib__SpotBalancePrecompileFailed();
    error PrecompileLib__VaultEquityPrecompileFailed();
    error PrecompileLib__WithdrawablePrecompileFailed();
    error PrecompileLib__DelegationsPrecompileFailed();
    error PrecompileLib__DelegatorSummaryPrecompileFailed();
    error PrecompileLib__MarkPxPrecompileFailed();
    error PrecompileLib__OraclePxPrecompileFailed();
    error PrecompileLib__SpotPxPrecompileFailed();
    error PrecompileLib__PerpAssetInfoPrecompileFailed();
    error PrecompileLib__SpotInfoPrecompileFailed();
    error PrecompileLib__TokenInfoPrecompileFailed();
    error PrecompileLib__TokenSupplyPrecompileFailed();
    error PrecompileLib__L1BlockNumberPrecompileFailed();
    error PrecompileLib__BboPrecompileFailed();
    error PrecompileLib__AccountMarginSummaryPrecompileFailed();
    error PrecompileLib__CoreUserExistsPrecompileFailed();
    error PrecompileLib__SpotIndexNotFound();
    error PrecompileLib__BorrowLendUserStatePrecompileFailed();
    error PrecompileLib__BorrowLendReserveStatePrecompileFailed();
}
