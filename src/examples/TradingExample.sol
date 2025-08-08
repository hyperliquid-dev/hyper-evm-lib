// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CoreWriterLib, HLConstants} from "@hyper-evm-lib/src/CoreWriterLib.sol";

/**
 * @title TradingExample
 * @dev This contract demonstrates CoreWriterLib trading functionality.
 */
contract TradingExample {
    using CoreWriterLib for *;

    uint64 public constant USDC_TOKEN_ID = 0;

    /**
     * @notice Places a limit order
     * @param asset Asset ID to trade
     * @param isBuy True for buy order, false for sell order
     * @param limitPx Limit price for the order
     * @param sz Size/quantity of the order
     * @param reduceOnly True if order should only reduce position
     * @param encodedTif Time in force encoding (1=ALO, 2=GTC, 3=IOC)
     * @param cloid Client order ID for tracking
     */
    function placeLimitOrder(
        uint32 asset,
        bool isBuy,
        uint64 limitPx,
        uint64 sz,
        bool reduceOnly,
        uint8 encodedTif,
        uint128 cloid
    ) external {
        CoreWriterLib.placeLimitOrder(asset, isBuy, limitPx, sz, reduceOnly, encodedTif, cloid);
    }

    /**
     * @notice Cancels an order by client order ID
     * @param asset Asset ID of the order to cancel
     * @param cloid Client order ID of the order to cancel
     */
    function cancelOrderByCloid(uint32 asset, uint128 cloid) external {
        CoreWriterLib.cancelOrderByCloid(asset, cloid);
    }

    /**
     * @notice Transfers USDC tokens to another address
     * @param to Address of the recipient
     * @param coreAmount Amount of USDC to transfer
     */
    function transferUsdc(address to, uint64 coreAmount) external {
        CoreWriterLib.spotSend(to, USDC_TOKEN_ID, coreAmount);
    }

    /**
     * @notice Transfers USDC between spot and perp trading accounts
     * @param coreAmount Amount to transfer //TODO: if core amount is passed in, we have to convert to perp amount first
     * @param toPerp If true, transfers from spot to perp; if false, transfers from perp to spot
     */
    function transferUsdcBetweenSpotAndPerp(uint64 coreAmount, bool toPerp) external {
        CoreWriterLib.transferUsdClass(coreAmount, toPerp);
    }

    /**
     * @notice Withdraws tokens from staking balance and bridges them back to EVM
     * @param evmAmount Amount of tokens to bridge back to EVM
     */
    function bridgeHypeBackToEvm(uint64 evmAmount) external {
        // Bridge tokens back to EVM
        CoreWriterLib.bridgeToEvm(HLConstants.hypeTokenIndex(), evmAmount, true);
    }

    receive() external payable {}
} 