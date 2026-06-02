// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PrecompileLib} from "./PrecompileLib.sol";
import {HLConstants} from "./common/HLConstants.sol";
import {HLConversions} from "./common/HLConversions.sol";

import {ICoreWriter} from "./interfaces/ICoreWriter.sol";
import {ICoreDepositWallet} from "./interfaces/ICoreDepositWallet.sol";

/**
 * @title CoreWriterLib v1.2
 * @author Obsidian (https://x.com/ObsidianAudits)
 * @notice Library for interacting with HyperEVM's CoreWriter (0x3333...3333).
 *
 * @dev Each CoreWriter action has two variants:
 *  - `encode*` returns the wire-format action bytes (version byte 0x01 ++ 3-byte action ID
 *    ++ ABI-encoded args) without sending. Useful for batching, off-chain inspection, or
 *    custom routing through alternate CoreWriter contracts.
 *  - The action helper (e.g. `placeLimitOrder`, `spotSend`) encodes and sends in one call.
 *
 * @dev Execution model:
 *  - CoreWriter actions are queued on submission and applied on the NEXT HyperCore block.
 *    Reads via PrecompileLib reflect the most recently committed Core state, so a value
 *    submitted in block N is not visible until block N+1.
 *  - Actions can fail silently on Core (e.g. insufficient balance, locked vault). The EVM
 *    submission only verifies the wire format; no on-EVM error is raised for Core-side
 *    rejections.
 *
 * @dev Amount conventions:
 *  - All `*Wei`/`amount`/`ntl`/`usd*` arguments are denominated in HyperCore's native
 *    precision (per-token `szDecimals` for sizes, `pxDecimals` for prices). Use
 *    `HLConversions` to translate between EVM (18-dec) and Core (token-defined) values.
 *
 *
 * @dev Fees & costs:
 *  - Trading actions (limit order, cancel) incur the standard Hyperliquid taker/maker fees
 *    on fill — no separate EVM-side cost beyond the CoreWriter call.
 *  - Cross-context transfers (`sendAsset` to a system address, `bridgeToEvm`) may incur
 *    Core-side fees to cover EVM execution; consult current Hyperliquid docs for exact
 *    semantics per token. Sender must hold sufficient HYPE/balance on Core or the action
 *    is rejected.
 *
 * @dev Additional functionality:
 *  - Bridging assets between EVM and HyperCore (`bridgeToCore`, `bridgeToEvm`)
 *  - Converting decimal representations between EVM and HyperCore amounts (via HLConversions)
 *  - Security checks before sending actions to CoreWriter (e.g. vault lock, self-transfer)
 */
library CoreWriterLib {
    using SafeERC20 for IERC20;

    ICoreWriter constant coreWriter = ICoreWriter(0x3333333333333333333333333333333333333333);

    error CoreWriterLib__StillLockedUntilTimestamp(uint64 lockedUntilTimestamp);
    error CoreWriterLib__CannotSelfTransfer();
    error CoreWriterLib__HypeTransferFailed();
    error CoreWriterLib__CoreAmountTooLarge(uint256 amount);
    error CoreWriterLib__EvmAmountTooSmall(uint256 amount);

    /*//////////////////////////////////////////////////////////////
                       EVM <---> Core Bridging
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bridges an ERC20 token from EVM to HyperCore using the token's address.
     * @param tokenAddress EVM contract address of the token (must be linked to a Core token index)
     * @param evmAmount Amount to bridge, in EVM (18-dec for HYPE, ERC20-defined for others)
     * @dev Reverts if the conversion to Core precision rounds to zero, to prevent dust loss.
     */
    function bridgeToCore(address tokenAddress, uint256 evmAmount) internal {
        uint64 tokenIndex = PrecompileLib.getTokenIndex(tokenAddress);
        bridgeToCore(tokenIndex, evmAmount);
    }

    /**
     * @notice Bridges a token from EVM to HyperCore by token index.
     * @param token Core token index
     * @param evmAmount Amount in EVM units (18-dec for HYPE, ERC20-defined for others)
     * @dev Routing:
     *  - USDC: forwarded via the CoreDepositWallet (always lands in caller's spot account)
     *  - HYPE: native value transfer to the HYPE system address
     *  - Other tokens: ERC20 transfer to the token's per-asset system address
     * @dev All tokens (including USDC) bridge to the spot DEX. Move to perp via
     *  `transferUsdClass` (USDC) or `sendAsset` (other tokens) once on Core.
     * @dev Reverts if the converted Core amount is zero (sub-dust EVM amount).
     */
    function bridgeToCore(uint64 token, uint256 evmAmount) internal {
        ICoreDepositWallet coreDepositWallet = ICoreDepositWallet(HLConstants.coreDepositWallet());

        // Check if amount would be 0 after conversion to prevent token loss
        uint64 coreAmount = HLConversions.evmToWei(token, evmAmount);
        if (coreAmount == 0) revert CoreWriterLib__EvmAmountTooSmall(evmAmount);
        address systemAddress = getSystemAddress(token);
        if (HLConstants.isUsdc(token)) {
            IERC20(HLConstants.usdc()).approve(address(coreDepositWallet), evmAmount);
            coreDepositWallet.deposit(evmAmount, uint32(type(uint32).max));
        } else if (isHype(token)) {
            (bool success,) = systemAddress.call{value: evmAmount}("");
            if (!success) revert CoreWriterLib__HypeTransferFailed();
        } else {
            PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(token));
            address tokenAddress = info.evmContract;
            IERC20(tokenAddress).safeTransfer(systemAddress, evmAmount);
        }
    }

    /**
     * @notice Bridges USDC from EVM to Core to a specific recipient
     * @param recipient The address that will receive the USDC on Core
     * @param evmAmount The amount of USDC to bridge (in EVM decimals)
     * @param destinationDex The dex to send the USDC to on Core (type(uint32).max for spot, 0 for default perp dex)
     */
    function bridgeUsdcToCoreFor(address recipient, uint256 evmAmount, uint32 destinationDex) internal {
        ICoreDepositWallet coreDepositWallet = ICoreDepositWallet(HLConstants.coreDepositWallet());

        // Check if amount would be 0 after conversion to prevent token loss
        uint64 coreAmount = HLConversions.evmToWei(HLConstants.USDC_TOKEN_INDEX, evmAmount);
        if (coreAmount == 0) revert CoreWriterLib__EvmAmountTooSmall(evmAmount);

        IERC20(HLConstants.usdc()).approve(address(coreDepositWallet), evmAmount);
        coreDepositWallet.depositFor(recipient, evmAmount, destinationDex);
    }

    /**
     * @notice Bridges a token from HyperCore back to EVM using the token's address.
     * @param tokenAddress EVM contract address (used to resolve the Core token index)
     * @param evmAmount Amount in EVM units
     * @dev Requires the caller's Core spot account to hold the amount. For non-HYPE tokens
     *  the caller must additionally hold a small HYPE balance on Core to cover the
     *  system-address transfer fee — otherwise the `sendAsset` action is silently rejected.
     */
    function bridgeToEvm(address tokenAddress, uint256 evmAmount) internal {
        uint64 tokenIndex = PrecompileLib.getTokenIndex(tokenAddress);
        bridgeToEvm(tokenIndex, evmAmount, true);
    }

    /**
     * @notice Bridges a token from HyperCore back to EVM by token index.
     * @param token Core token index
     * @param amount Amount to bridge. Interpretation depends on `isEvmAmount`.
     * @param isEvmAmount If true, `amount` is in EVM units and is converted to Core precision;
     *  if false, `amount` is already in Core precision (must fit in uint64).
     * @dev NON-HYPE bridging: the caller's Core spot account must hold a small HYPE balance
     *  to cover the system-address transfer fee. The bridge is implemented as a `sendAsset`
     *  to the token's per-asset system address; the HYPE fee mirrors a standard Core spot
     *  transfer fee. Without sufficient HYPE the action is silently rejected on Core.
     * @dev Reverts if a Core-precision amount would be zero, or if a raw Core amount exceeds
     *  uint64.
     */
    function bridgeToEvm(uint64 token, uint256 amount, bool isEvmAmount) internal {
        uint64 coreAmount;
        if (isEvmAmount) {
            coreAmount = HLConversions.evmToWei(token, amount);
            if (coreAmount == 0) revert CoreWriterLib__EvmAmountTooSmall(amount);
        } else {
            if (amount > type(uint64).max) revert CoreWriterLib__CoreAmountTooLarge(amount);
            coreAmount = uint64(amount);
        }

        sendAsset(getSystemAddress(token), address(0), HLConstants.SPOT_DEX, HLConstants.SPOT_DEX, token, coreAmount);
    }

    /*//////////////////////////////////////////////////////////////
                          Bridging Utils
    //////////////////////////////////////////////////////////////*/

    function getSystemAddress(uint64 index) internal view returns (address) {
        if (index == HLConstants.hypeTokenIndex()) {
            return HLConstants.HYPE_SYSTEM_ADDRESS;
        }
        return address(HLConstants.BASE_SYSTEM_ADDRESS + index);
    }

    function isHype(uint64 index) internal view returns (bool) {
        return index == HLConstants.hypeTokenIndex();
    }

    function toMilliseconds(uint64 timestamp) internal pure returns (uint64) {
        return timestamp * 1000;
    }

    function _canWithdrawFromVault(address vault) internal view returns (bool, uint64) {
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(address(this), vault);

        return
            (
                toMilliseconds(uint64(block.timestamp)) > vaultEquity.lockedUntilTimestamp,
                vaultEquity.lockedUntilTimestamp
            );
    }

    /*//////////////////////////////////////////////////////////////
                              Encoders
        Each encoder returns the CoreWriter wire format: 1-byte version
        (0x01) ++ 3-byte action ID ++ abi-encoded args. Implemented via
        `abi.encodeWithSelector(SELECTOR, args...)` where each SELECTOR
        is bytes4 of (0x01 ++ action ID) — single allocation, no nested
        abi.encode.
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Encodes a limit order action.
     * @param asset Asset index. For perp: perp index. For spot: `10000 + spotIndex`
     *  (Hyperliquid convention for routing through the spot order book).
     * @param isBuy True for buy, false for sell.
     * @param limitPx Limit price in raw Core units (per-asset `pxDecimals`).
     * @param sz Order size in raw Core units (per-asset `szDecimals`).
     * @param reduceOnly Reduce-only flag. Ignored on spot orders.
     * @param encodedTif Time-in-force: 1=ALO (post-only), 2=GTC, 3=IOC. See
     *  `HLConstants.LIMIT_ORDER_TIF_*`.
     * @param cloid Client order ID. 0 for none. Used by `cancelOrderByCloid`.
     * @dev Standard taker/maker fees apply on fill; fee tier is per-account on Core.
     */
    function encodeLimitOrder(
        uint32 asset,
        bool isBuy,
        uint64 limitPx,
        uint64 sz,
        bool reduceOnly,
        uint8 encodedTif,
        uint128 cloid
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            HLConstants.LIMIT_ORDER_ACTION, asset, isBuy, limitPx, sz, reduceOnly, encodedTif, cloid
        );
    }

    /**
     * @notice Encodes a vault deposit or withdrawal.
     * @param vault Vault address on Core.
     * @param isDeposit True deposits USDC into the vault, false withdraws.
     * @param usdAmount USDC amount in 6-dec Core units.
     * @dev Withdrawals are blocked until the vault's `lockedUntilTimestamp` has elapsed —
     *  the `vaultTransfer` helper enforces this on EVM before submitting.
     */
    function encodeVaultTransfer(address vault, bool isDeposit, uint64 usdAmount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.VAULT_TRANSFER_ACTION, vault, isDeposit, usdAmount);
    }

    /**
     * @notice Encodes a token delegation (stake to / unstake from a validator).
     * @param validator Validator address.
     * @param amountWei HYPE amount in 8-dec Core units.
     * @param undelegate False to delegate, true to undelegate.
     * @dev Undelegation triggers a ~7 day unbonding period before the HYPE becomes
     *  withdrawable from the staking pool.
     */
    function encodeTokenDelegate(address validator, uint64 amountWei, bool undelegate)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(HLConstants.TOKEN_DELEGATE_ACTION, validator, amountWei, undelegate);
    }

    /**
     * @notice Encodes a staking deposit (moves HYPE from spot account into staking pool).
     * @param amountWei HYPE amount in 8-dec Core units.
     */
    function encodeStakingDeposit(uint64 amountWei) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.STAKING_DEPOSIT_ACTION, amountWei);
    }

    /**
     * @notice Encodes a staking withdrawal (moves HYPE from staking pool back to spot).
     * @param amountWei HYPE amount in 8-dec Core units.
     * @dev Requires prior undelegation; subject to a ~7 day unbonding period after undelegate.
     */
    function encodeStakingWithdraw(uint64 amountWei) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.STAKING_WITHDRAW_ACTION, amountWei);
    }

    /**
     * @notice Encodes a spot-account transfer to another Core account.
     * @param to Recipient address (must differ from the sending account).
     * @param token Core token index.
     * @param amountWei Amount in the token's Core precision.
     * @dev Sends from the caller's spot account. The `spotSend` helper rejects
     *  self-transfers (Core would reject them anyway). Refer to current Hyperliquid docs
     *  for any fee schedule.
     */
    function encodeSpotSend(address to, uint64 token, uint64 amountWei) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.SPOT_SEND_ACTION, to, token, amountWei);
    }

    /**
     * @notice Encodes a USDC class transfer between spot and perp accounts.
     * @param ntl USDC notional in 6-dec Core units.
     * @param toPerp True moves USDC spot → perp; false moves perp → spot.
     * @dev Perp → spot transfers are constrained by maintenance margin: Core will reject
     *  the action if the withdrawal would put the perp account below margin.
     */
    function encodeUsdClassTransfer(uint64 ntl, bool toPerp) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.USD_CLASS_TRANSFER_ACTION, ntl, toPerp);
    }

    /**
     * @notice Encodes a finalize-EVM-contract action, linking a Core token to an EVM contract.
     * @param token Core token index to finalize.
     * @param encodedVariant Finalization variant: 1=Create (use deployer + nonce), 2=FirstStorageSlot,
     *  3=CustomStorageSlot.
     * @param createNonce For Create variant, the deployer account nonce at contract creation.
     * @dev One-shot per token. Subsequent calls for the same token are no-ops on Core.
     */
    function encodeFinalizeEvmContract(uint64 token, uint8 encodedVariant, uint64 createNonce)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(HLConstants.FINALIZE_EVM_CONTRACT_ACTION, token, encodedVariant, createNonce);
    }

    /**
     * @notice Encodes an API wallet (agent) registration for the calling Core account.
     * @param wallet Agent address.
     * @param name Optional human-readable name. Empty string registers the main/default agent.
     */
    function encodeAddApiWallet(address wallet, string memory name) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.ADD_API_WALLET_ACTION, wallet, name);
    }

    /**
     * @notice Encodes a cancel-by-order-ID action.
     * @param asset Asset index (same convention as `encodeLimitOrder`).
     * @param orderId Core-assigned order ID.
     * @dev Async like all CoreWriter actions: cancellation applies on the next Core block.
     *  Partially-filled orders are cancelled for the remaining size only.
     */
    function encodeCancelOrderByOid(uint32 asset, uint64 orderId) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.CANCEL_ORDER_BY_OID_ACTION, asset, orderId);
    }

    /**
     * @notice Encodes a cancel-by-client-order-ID action.
     * @param asset Asset index (same convention as `encodeLimitOrder`).
     * @param cloid Client order ID supplied at placement.
     */
    function encodeCancelOrderByCloid(uint32 asset, uint128 cloid) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.CANCEL_ORDER_BY_CLOID_ACTION, asset, cloid);
    }

    /**
     * @notice Encodes a builder-fee approval for a specific builder address.
     * @param maxFeeRate Maximum rate in decibps (10 = 0.01%). Builders cannot charge more
     *  than this on fills routed through them.
     * @param builder Builder address being authorized.
     */
    function encodeApproveBuilderFee(uint64 maxFeeRate, address builder) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(HLConstants.APPROVE_BUILDER_FEE_ACTION, maxFeeRate, builder);
    }

    /**
     * @notice Encodes a cross-account / cross-DEX asset transfer.
     * @param destination Receiving Core address. Can be a system address (for bridging out
     *  to EVM), a sub-account, or another user.
     * @param subAccount If non-zero, transfers go to/from this sub-account of the caller.
     *  Pass `address(0)` for main-account transfers.
     * @param source_dex Source DEX: `HLConstants.SPOT_DEX` for spot, `0` for default perp,
     *  or a HIP-3 perp DEX index.
     * @param destination_dex Destination DEX (same encoding as `source_dex`).
     * @param token Core token index.
     * @param amountWei Amount in the token's Core precision.
     * @dev FEE QUIRK: transferring NON-HYPE tokens to the per-asset system address (the
     *  pattern used by `bridgeToEvm`) charges a small HYPE-denominated transfer fee from
     *  the sender's Core spot account. Sender must hold sufficient HYPE on Core or the
     *  action is silently rejected. HYPE transfers themselves are exempt from this fee.
     *  Cross-DEX (spot ↔ perp) movements that don't touch a system address don't incur
     *  the system-address fee.
     */
    function encodeSendAsset(
        address destination,
        address subAccount,
        uint32 source_dex,
        uint32 destination_dex,
        uint64 token,
        uint64 amountWei
    ) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(
            HLConstants.SEND_ASSET_ACTION, destination, subAccount, source_dex, destination_dex, token, amountWei
        );
    }

    /**
     * @notice Encodes a supply-change reflection for an aligned-quote ERC20.
     * @param token Core token index of the aligned quote token (e.g. USDC).
     * @param amount Amount in the token's Core precision.
     * @param isMint True reflects an EVM mint (credit Core supply), false reflects a burn.
     * @dev Only the linked EVM contract for the aligned quote token can submit this — Core
     *  validates the caller against the finalized EVM contract address.
     */
    function encodeReflectEvmSupplyChange(uint64 token, uint64 amount, bool isMint)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(HLConstants.REFLECT_EVM_SUPPLY_CHANGE_ACTION, token, amount, isMint);
    }

    /**
     * @notice Encodes a supply (lend) or withdraw operation against Core's borrow/lend market.
     * @param encodedOperation `HLConstants.BLP_SUPPLY` (0) supplies, `BLP_WITHDRAW` (1) withdraws.
     * @param token Core token index.
     * @param amountWei Amount in the token's Core precision. Pass 0 to apply maximally
     *  (e.g. withdraw the caller's full supplied balance).
     */
    function encodeBorrowLend(uint8 encodedOperation, uint64 token, uint64 amountWei)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(HLConstants.BORROW_LEND_OPERATION_ACTION, encodedOperation, token, amountWei);
    }

    /*//////////////////////////////////////////////////////////////
                              Staking
    //////////////////////////////////////////////////////////////*/

    /// @notice Delegates (or undelegates) HYPE from the caller's staking pool to a validator.
    /// @dev Undelegation starts a ~7 day unbonding period before HYPE can be withdrawn back
    ///  to the spot account. See `encodeTokenDelegate` for parameter semantics.
    function delegateToken(address validator, uint64 amountWei, bool undelegate) internal {
        coreWriter.sendRawAction(encodeTokenDelegate(validator, amountWei, undelegate));
    }

    /// @notice Moves HYPE from the caller's spot account into the staking pool.
    /// @dev Required before `delegateToken` can stake to a validator.
    function depositStake(uint64 amountWei) internal {
        coreWriter.sendRawAction(encodeStakingDeposit(amountWei));
    }

    /// @notice Moves HYPE from the staking pool back to the caller's spot account.
    /// @dev Only succeeds for amounts past the ~7 day unbonding period after undelegate.
    function withdrawStake(uint64 amountWei) internal {
        coreWriter.sendRawAction(encodeStakingWithdraw(amountWei));
    }

    /*//////////////////////////////////////////////////////////////
                              Trading
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposits USDC into a vault or withdraws from one.
    /// @dev On withdrawal, reverts on EVM with `CoreWriterLib__StillLockedUntilTimestamp` if
    ///  the vault's lock period has not elapsed (checked via VAULT_EQUITY precompile). This
    ///  is a UX guardrail — Core would silently reject the action otherwise.
    function vaultTransfer(address vault, bool isDeposit, uint64 usdAmount) internal {
        if (!isDeposit) {
            (bool canWithdraw, uint64 lockedUntilTimestamp) = _canWithdrawFromVault(vault);

            if (!canWithdraw) revert CoreWriterLib__StillLockedUntilTimestamp(lockedUntilTimestamp);
        }

        coreWriter.sendRawAction(encodeVaultTransfer(vault, isDeposit, usdAmount));
    }

    /// @notice Moves USDC between the caller's spot and perp accounts on Core.
    /// @dev Perp → spot transfers can be silently rejected if they would breach maintenance
    ///  margin. Check `accountMarginSummary` before withdrawing margin.
    function transferUsdClass(uint64 ntl, bool toPerp) internal {
        coreWriter.sendRawAction(encodeUsdClassTransfer(ntl, toPerp));
    }

    /// @notice Places a limit order on the perp or spot order book.
    /// @dev See `encodeLimitOrder` for parameter semantics. Asynchronous: matched on the
    ///  next Core block. Standard taker/maker fees apply on fill.
    function placeLimitOrder(
        uint32 asset,
        bool isBuy,
        uint64 limitPx,
        uint64 sz,
        bool reduceOnly,
        uint8 encodedTif,
        uint128 cloid
    ) internal {
        coreWriter.sendRawAction(encodeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, encodedTif, cloid));
    }

    /// @notice Registers an API wallet (agent) for the calling Core account.
    /// @param name Empty string registers the main/default agent.
    function addApiWallet(address wallet, string memory name) internal {
        coreWriter.sendRawAction(encodeAddApiWallet(wallet, name));
    }

    /// @notice Cancels a previously placed order by Core-assigned order ID.
    function cancelOrderByOrderId(uint32 asset, uint64 orderId) internal {
        coreWriter.sendRawAction(encodeCancelOrderByOid(asset, orderId));
    }

    /// @notice Cancels a previously placed order by client order ID (cloid).
    function cancelOrderByCloid(uint32 asset, uint128 cloid) internal {
        coreWriter.sendRawAction(encodeCancelOrderByCloid(asset, cloid));
    }

    /// @notice Links a Core token to an EVM contract address. One-shot per token.
    /// @dev See `encodeFinalizeEvmContract` for variant/nonce semantics.
    function finalizeEvmContract(uint64 token, uint8 encodedVariant, uint64 createNonce) internal {
        coreWriter.sendRawAction(encodeFinalizeEvmContract(token, encodedVariant, createNonce));
    }

    /// @notice Authorizes a builder to charge fees on trades up to `maxFeeRate` decibps.
    function approveBuilderFee(uint64 maxFeeRate, address builder) internal {
        coreWriter.sendRawAction(encodeApproveBuilderFee(maxFeeRate, builder));
    }

    /**
     * @notice Cross-account / cross-DEX / cross-sub-account asset transfer on Core.
     * @dev See `encodeSendAsset` for parameter semantics.
     *  FEE QUIRK (NON-HYPE tokens to system address): a small HYPE-denominated fee is
     *  deducted from the sender's Core spot account. Sender must hold enough HYPE on Core
     *  or the transfer is silently rejected. Used by `bridgeToEvm` for non-HYPE tokens.
     */
    function sendAsset(
        address destination,
        address subAccount,
        uint32 source_dex,
        uint32 destination_dex,
        uint64 token,
        uint64 amountWei
    ) internal {
        coreWriter.sendRawAction(
            encodeSendAsset(destination, subAccount, source_dex, destination_dex, token, amountWei)
        );
    }

    /**
     * @notice Sends a spot asset from the caller's Core spot account to another address.
     * @dev Reverts on EVM if `to == address(this)` since Core would reject self-transfers
     *  anyway.
     */
    function spotSend(address to, uint64 token, uint64 amountWei) internal {
        if (to == address(this)) revert CoreWriterLib__CannotSelfTransfer();
        coreWriter.sendRawAction(encodeSpotSend(to, token, amountWei));
    }

    /*//////////////////////////////////////////////////////////////
                       Reflect EVM Supply Change
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reflects an EVM-side mint/burn of an aligned quote token on HyperCore.
     * @param token Core token index of the aligned quote token (e.g. USDC).
     * @param amount Amount in the token's Core precision.
     * @param isMint True for mint on Core (after EVM mint), false for burn on Core
     *  (after EVM burn). Keeps EVM and Core supplies in sync.
     * @dev Only the finalized EVM contract for the aligned token can submit this — Core
     *  rejects calls from any other origin.
     */
    function reflectEvmSupplyChange(uint64 token, uint64 amount, bool isMint) internal {
        coreWriter.sendRawAction(encodeReflectEvmSupplyChange(token, amount, isMint));
    }

    /*//////////////////////////////////////////////////////////////
                            Borrow/Lend
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Supplies to or withdraws from Core's borrow/lend market.
     * @param encodedOperation `HLConstants.BLP_SUPPLY` (0) or `BLP_WITHDRAW` (1).
     * @param token Core token index.
     * @param amountWei Amount in the token's Core precision; 0 applies the operation
     *  maximally (e.g. withdraw full supplied balance).
     */
    function borrowLend(uint8 encodedOperation, uint64 token, uint64 amountWei) internal {
        coreWriter.sendRawAction(encodeBorrowLend(encodedOperation, token, amountWei));
    }
}
