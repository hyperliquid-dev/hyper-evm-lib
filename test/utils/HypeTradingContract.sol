// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CoreWriterLib} from "../../src/CoreWriterLib.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {HLConstants} from "../../src/common/HLConstants.sol";

/**
 * @title HypeTradingContract
 * @dev A simple contract to place HYPE limit orders and view position data
 */
contract HypeTradingContract {
    using CoreWriterLib for *;

    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner, "Only authorized user can call this function");
        _;
    }

    /**
     * @notice Get the HYPE token index based on current chain
     * @return HYPE token index (1105 for mainnet, 150 for testnet)
     */
    function getHypeTokenIndex() public view returns (uint64) {
        return HLConstants.hypeTokenIndex();
    }

    /**
     * @notice Places a limit order for any perp asset (can be used for both buy and sell orders)
     * @param perpId Perpetual asset ID to trade
     * @param isBuy True for buy/long position, false for sell/short position
     * @param limitPx Limit price for the order (set very high for market buy, very low for market sell)
     * @param sz Size/quantity of the order
     * @param reduceOnly True if order should only reduce existing position, false to open new position
     * @param cloid Client order ID for tracking
     */
    function createLimitOrder(uint32 perpId, bool isBuy, uint64 limitPx, uint64 sz, bool reduceOnly, uint128 cloid)
        external
        onlyAuthorized
    {
        CoreWriterLib.placeLimitOrder(
            perpId,
            isBuy,
            limitPx,
            sz,
            reduceOnly,
            HLConstants.LIMIT_ORDER_TIF_IOC, // IOC for immediate execution (market-like behavior)
            cloid
        );
    }

    /**
     * @notice View function to get position data from the position precompile
     * @param user Address of the user to get position for
     * @param perpIndex Perp index (use HYPE_ASSET_ID or other perp asset)
     * @return position Position data including size, entry price, PnL, leverage, and isolation status
     */
    function getPosition(address user, uint16 perpIndex)
        external
        view
        returns (PrecompileLib.Position memory position)
    {
        return PrecompileLib.position(user, perpIndex);
    }

    /**
     * @notice Get position for a user for any perp asset
     * @param user Address of the user
     * @param perpIndex Perp index to get position for
     * @return position Position data for the specified perp
     */
    function getUserPosition(address user, uint16 perpIndex)
        external
        view
        returns (PrecompileLib.Position memory position)
    {
        return PrecompileLib.position(user, perpIndex);
    }

    /**
     * @notice Cancel an order by client order ID
     * @param perpId Perpetual asset ID of the order to cancel
     * @param cloid Client order ID to cancel
     */
    function cancelOrder(uint32 perpId, uint128 cloid) external onlyAuthorized {
        CoreWriterLib.cancelOrderByCloid(perpId, cloid);
    }

    /**
     * @notice Get account margin summary for trading
     * @param user Address of the user
     * @return marginSummary Account margin data including account value, margin used, etc.
     */
    function getAccountMarginSummary(address user)
        external
        view
        returns (PrecompileLib.AccountMarginSummary memory marginSummary)
    {
        // Use perpDexIndex = 0 for main perp dex
        return PrecompileLib.accountMarginSummary(0, user);
    }

    /**
     * @notice Transfer USDC between spot and perp trading accounts
     * @param ntl Amount to transfer (in core decimals)
     * @param toPerp If true, transfers from spot to perp; if false, transfers from perp to spot
     */
    function transferUsdClass(uint64 ntl, bool toPerp) external onlyAuthorized {
        CoreWriterLib.transferUsdClass(ntl, toPerp);
    }

    /**
     * @notice Send USDC to another address via spot transfer
     * @param to Address of the recipient
     * @param coreAmount Amount of USDC to transfer (in core decimals)
     */
    function spotSendUsdc(address to, uint64 coreAmount) external onlyAuthorized {
        uint64 usdcTokenId = 0; // USDC token ID is 0
        CoreWriterLib.spotSend(to, usdcTokenId, coreAmount);
    }

    /**
     * @notice Send any token to another address via spot transfer
     * @param to Address of the recipient
     * @param token Token ID to transfer
     * @param coreAmount Amount to transfer (in core decimals)
     */
    function spotSend(address to, uint64 token, uint64 coreAmount) external onlyAuthorized {
        CoreWriterLib.spotSend(to, token, coreAmount);
    }
}
