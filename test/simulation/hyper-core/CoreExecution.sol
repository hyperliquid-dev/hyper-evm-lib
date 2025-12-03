// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Heap} from "@openzeppelin/contracts/utils/structs/Heap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";
import {HLConversions} from "../../../src/common/HLConversions.sol";
import {RealL1Read} from "../../utils/RealL1Read.sol";
import {CoreView} from "./CoreView.sol";

contract CoreExecution is CoreView {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Heap for Heap.Uint256Heap;
    using SafeERC20 for IERC20;
    using RealL1Read for *;

    using EnumerableSet for EnumerableSet.UintSet;

    function _getKey(address user, uint16 perpIndex) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(user)) << 16) | uint256(perpIndex));
    }

    function executeTokenTransfer(address, uint64 token, address from, uint256 value)
        public
        payable
        initAccountWithToken(from, token)
    {
        if (_accounts[from].activated) {
            _accounts[from].spot[token] += toWei(value, _tokens[token].evmExtraWeiDecimals);
        } else {
            _latentSpotBalance[from][token] += toWei(value, _tokens[token].evmExtraWeiDecimals);
        }
    }

    function executeNativeTransfer(address, address from, uint256 value)
        public
        payable
        initAccountWithToken(from, HYPE_TOKEN_INDEX)
    {
        if (_accounts[from].activated) {
            _accounts[from].spot[HYPE_TOKEN_INDEX] += (value / 1e10).toUint64();
        } else {
            _latentSpotBalance[from][HYPE_TOKEN_INDEX] += (value / 1e10).toUint64();
        }
    }

    function executePerpLimitOrder(address sender, LimitOrderAction memory action)
        public
        initAccountWithPerp(sender, uint16(action.asset))
    {
        uint16 perpIndex = uint16(action.asset);
        PrecompileLib.Position memory position = _accounts[sender].positions[perpIndex];

        bool isolated = position.isIsolated;

        uint256 markPx = PrecompileLib.markPx(perpIndex);
        uint256 normalizedMarkPx = PrecompileLib.normalizedMarkPx(perpIndex) * 100;

        PrecompileLib.PerpAssetInfo memory perpInfo = PrecompileLib.perpAssetInfo(perpIndex);
        action.sz = scale(action.sz, 8, perpInfo.szDecimals);

        if (!isolated) {
            if (action.isBuy) {
                if (normalizedMarkPx <= action.limitPx) {
                    _updateMarginSummary(sender);
                    _executePerpLong(sender, action, markPx);
                    _updateMarginSummary(sender);
                }
            } else {
                if (normalizedMarkPx >= action.limitPx) {
                    _updateMarginSummary(sender);
                    _executePerpShort(sender, action, markPx);
                    _updateMarginSummary(sender);
                }
            }
        }
    }

    function _executePerpLong(address sender, LimitOrderAction memory action, uint256 markPx) internal {
        uint16 perpIndex = uint16(action.asset);
        int64 szi = _accounts[sender].positions[perpIndex].szi;
        uint32 leverage = _accounts[sender].positions[perpIndex].leverage;

        uint64 _markPx = markPx.toUint64();

        // Add require checks for safety (e.g., leverage > 0, action.sz > 0, etc.)
        require(leverage > 0, "Invalid leverage");
        require(action.sz > 0, "Invalid size");
        require(markPx > 0, "Invalid price");

        if (perpTakerFeeBps > 0) {
            uint256 notional = uint256(action.sz) * uint256(_markPx);
            uint64 fee = SafeCast.toUint64((notional * uint256(perpTakerFeeBps)) / 10_000);
            require(_accounts[sender].perpBalance >= fee, "insufficient perp balance for fee");
            _accounts[sender].perpBalance -= fee;
        }

        int64 newSzi = szi + int64(action.sz);

        if (szi >= 0) {
            // No PnL realization for same-direction increase
            // Update position size (more positive for long)
            _accounts[sender].positions[perpIndex].szi += int64(action.sz);

            // Additive update to entryNtl to preserve weighted average
            // New entryNtl = old_entryNtl + (action.sz * markPx)
            _accounts[sender].positions[perpIndex].entryNtl += uint64(action.sz) * uint64(markPx);
        } else {
            if (newSzi <= 0) {
                uint64 avgEntryPrice = _accounts[sender].positions[perpIndex].entryNtl / uint64(-szi);
                int64 pnl = int64(action.sz) * (int64(avgEntryPrice) - int64(_markPx));

                uint64 closedMargin =
                    (uint64(action.sz) * _accounts[sender].positions[perpIndex].entryNtl / uint64(-szi)) / leverage;

                _accounts[sender].perpBalance = pnl > 0
                    ? _accounts[sender].perpBalance + uint64(pnl)
                    : _accounts[sender].perpBalance - uint64(-pnl);

                _accounts[sender].positions[perpIndex].szi = newSzi;
                _accounts[sender].positions[perpIndex].entryNtl = uint64(-newSzi) * avgEntryPrice;
            } else {
                uint64 avgEntryPrice = _accounts[sender].positions[perpIndex].entryNtl / uint64(-szi);
                int64 pnl = int64(-szi) * (int64(avgEntryPrice) - int64(_markPx));
                _accounts[sender].perpBalance = pnl > 0
                    ? _accounts[sender].perpBalance + uint64(pnl)
                    : _accounts[sender].perpBalance - uint64(-pnl);

                uint64 newLongSize = uint64(newSzi);
                uint64 newMargin = newLongSize * _markPx / leverage;

                _accounts[sender].positions[perpIndex].szi = newSzi;
                _accounts[sender].positions[perpIndex].entryNtl = newLongSize * _markPx;
            }
        }

        bytes32 key = _getKey(sender, perpIndex);
        if (szi == 0 && newSzi != 0) {
            _openPerpPositions.add(key);
            _userPerpPositions[sender].add(perpIndex);
        } else if (szi != 0 && newSzi == 0) {
            _openPerpPositions.remove(key);
            _userPerpPositions[sender].remove(perpIndex);
        }
    }

    function _executePerpShort(address sender, LimitOrderAction memory action, uint256 markPx) internal {
        uint16 perpIndex = uint16(action.asset);
        int64 szi = _accounts[sender].positions[perpIndex].szi;
        uint32 leverage = _accounts[sender].positions[perpIndex].leverage;

        uint64 _markPx = markPx.toUint64();

        // Add require checks for safety (e.g., leverage > 0, action.sz > 0, etc.)
        require(leverage > 0, "Invalid leverage");
        require(action.sz > 0, "Invalid size");
        require(markPx > 0, "Invalid price");

        if (perpTakerFeeBps > 0) {
            uint256 notional = uint256(action.sz) * uint256(_markPx);
            uint64 fee = SafeCast.toUint64((notional * uint256(perpTakerFeeBps)) / 10_000);
            require(_accounts[sender].perpBalance >= fee, "insufficient perp balance for fee");
            _accounts[sender].perpBalance -= fee;
        }

        int64 newSzi = szi - int64(action.sz);

        if (szi <= 0) {
            // No PnL realization for same-direction increase
            // Update position size (more negative for short)
            _accounts[sender].positions[perpIndex].szi -= int64(action.sz);

            // Additive update to entryNtl to preserve weighted average
            // New entryNtl = old_entryNtl + (action.sz * markPx)
            _accounts[sender].positions[perpIndex].entryNtl += uint64(action.sz) * uint64(markPx);
        } else {
            if (newSzi >= 0) {
                uint64 avgEntryPrice = _accounts[sender].positions[perpIndex].entryNtl / uint64(szi);
                int64 pnl = int64(action.sz) * (int64(_markPx) - int64(avgEntryPrice));
                uint64 closedMargin =
                    (uint64(action.sz) * _accounts[sender].positions[perpIndex].entryNtl / uint64(szi)) / leverage;

                _accounts[sender].perpBalance = pnl > 0
                    ? _accounts[sender].perpBalance + uint64(pnl)
                    : _accounts[sender].perpBalance - uint64(-pnl);

                _accounts[sender].positions[perpIndex].szi = newSzi;
                _accounts[sender].positions[perpIndex].entryNtl = uint64(newSzi) * avgEntryPrice;
            } else {
                uint64 avgEntryPrice = _accounts[sender].positions[perpIndex].entryNtl / uint64(szi);
                int64 pnl = int64(szi) * (int64(_markPx) - int64(avgEntryPrice));
                _accounts[sender].perpBalance = pnl > 0
                    ? _accounts[sender].perpBalance + uint64(pnl)
                    : _accounts[sender].perpBalance - uint64(-pnl);

                uint64 newShortSize = uint64(-newSzi);
                uint64 newMargin = newShortSize * _markPx / leverage;

                _accounts[sender].positions[perpIndex].szi = newSzi;
                _accounts[sender].positions[perpIndex].entryNtl = newShortSize * _markPx;
            }
        }

        bytes32 key = _getKey(sender, perpIndex);
        if (szi == 0 && newSzi != 0) {
            _openPerpPositions.add(key);
            _userPerpPositions[sender].add(perpIndex);
        } else if (szi != 0 && newSzi == 0) {
            _openPerpPositions.remove(key);
            _userPerpPositions[sender].remove(perpIndex);
        }
    }

    function _updateMarginSummary(address sender) internal {
        uint64 totalNtlPos = 0;
        uint64 totalMarginUsed = 0;

        uint64 entryNtlByLeverage = 0;

        uint64 totalLongNtlPos = 0;
        uint64 totalShortNtlPos = 0;

        for (uint256 i = 0; i < _userPerpPositions[sender].length(); i++) {
            uint16 perpIndex = uint16(_userPerpPositions[sender].at(i));

            PrecompileLib.Position memory position = _accounts[sender].positions[perpIndex];

            uint32 leverage = position.leverage;
            uint64 markPx = readMarkPx(perpIndex);

            entryNtlByLeverage += position.entryNtl / leverage;

            int64 szi = position.szi;

            if (szi > 0) {
                uint64 ntlPos = uint64(szi) * markPx;
                totalNtlPos += ntlPos;
                totalMarginUsed += ntlPos / leverage;

                totalLongNtlPos += ntlPos;
            } else if (szi < 0) {
                uint64 ntlPos = uint64(-szi) * markPx;
                totalNtlPos += ntlPos;
                totalMarginUsed += ntlPos / leverage;

                totalShortNtlPos += ntlPos;
            }
        }

        int64 totalAccountValue = int64(_accounts[sender].perpBalance - entryNtlByLeverage + totalMarginUsed);
        int64 totalRawUsd = totalAccountValue - int64(totalLongNtlPos) + int64(totalShortNtlPos);

        _accounts[sender].marginSummary[0] = PrecompileLib.AccountMarginSummary({
            accountValue: totalAccountValue, marginUsed: totalMarginUsed, ntlPos: totalNtlPos, rawUsd: totalRawUsd
        });
    }

    // basic simulation of spot trading, not accounting for orderbook depth, or fees
    function executeSpotLimitOrder(address sender, LimitOrderAction memory action)
        public
        initAccountWithSpotMarket(sender, uint32(HLConversions.assetToSpotId(action.asset)))
    {
        uint32 spotMarketId = uint32(HLConversions.assetToSpotId(action.asset));

        PrecompileLib.SpotInfo memory spotInfo = RealL1Read.spotInfo(spotMarketId);
        uint64 baseToken = spotInfo.tokens[0];
        uint64 quoteToken = spotInfo.tokens[1];

        uint8 baseSzDecimals = _tokens[baseToken].szDecimals;
        uint8 baseWeiDecimals = _tokens[baseToken].weiDecimals;

        uint64 spotPx = readSpotPx(spotMarketId) * SafeCast.toUint64(10 ** baseSzDecimals);

        if (spotPx == 0 && !useRealL1Read) {
            // in offline mode, if price is not set, we revert
            revert("Offline mode: spot price has not been set. Use CoreSimulatorLib.setSpotPx()");
        }

        if (isActionExecutable(action, spotPx)) {
            uint64 orderSz = action.sz;
            if (action.isBuy) {
                _executeSpotBuy(sender, baseToken, quoteToken, baseWeiDecimals, spotPx, orderSz);
            } else {
                _executeSpotSell(sender, baseToken, quoteToken, baseWeiDecimals, spotPx, orderSz);
            }
        } else {
            _pendingOrders.push(PendingOrder({sender: sender, action: action}));
        }
    }

    function _executeSpotBuy(
        address sender,
        uint64 baseToken,
        uint64 quoteToken,
        uint8 baseWeiDecimals,
        uint64 spotPx,
        uint64 orderSz
    ) internal {
        uint64 amountIn = SafeCast.toUint64(uint256(orderSz) * uint256(spotPx) / 1e8);
        uint64 amountOut = scale(orderSz, 8, baseWeiDecimals);

        uint64 totalDebit = amountIn;
        if (spotTakerFeeBps > 0) {
            totalDebit =
                SafeCast.toUint64(uint256(amountIn) + ((uint256(amountIn) * uint256(spotTakerFeeBps)) / 10_000));
        }

        if (_accounts[sender].spot[quoteToken] < totalDebit) {
            revert("insufficient balance");
        }

        _accounts[sender].spot[quoteToken] -= totalDebit;
        _accounts[sender].spot[baseToken] += amountOut;
    }

    function _executeSpotSell(
        address sender,
        uint64 baseToken,
        uint64 quoteToken,
        uint8 baseWeiDecimals,
        uint64 spotPx,
        uint64 orderSz
    ) internal {
        uint64 amountIn = scale(orderSz, 8, baseWeiDecimals);
        uint64 amountOut = SafeCast.toUint64(uint256(orderSz) * uint256(spotPx) / 1e8);

        if (_accounts[sender].spot[baseToken] < amountIn) {
            revert("insufficient balance");
        }

        uint64 netProceeds = amountOut;
        if (spotTakerFeeBps > 0) {
            uint64 fee = SafeCast.toUint64((uint256(amountOut) * uint256(spotTakerFeeBps)) / 10_000);
            require(netProceeds > fee, "fee exceeds proceeds");
            netProceeds -= fee;
        }

        _accounts[sender].spot[baseToken] -= amountIn;
        _accounts[sender].spot[quoteToken] += netProceeds;
    }

    function scale(uint64 amount, uint8 fromDecimals, uint8 toDecimals) internal pure returns (uint64) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            uint8 diff = toDecimals - fromDecimals;
            return amount * uint64(10) ** diff;
        } else {
            uint8 diff = fromDecimals - toDecimals;
            return amount / (uint64(10) ** diff);
        }
    }

    function executeSpotSend(address sender, SpotSendAction memory action)
        public
        initAccountWithToken(sender, action.token)
        whenActivated(sender)
        initAccountWithToken(action.destination, action.token)
    {
        if (action._wei > _accounts[sender].spot[action.token]) {
            revert("insufficient balance");
        }

        // handle account activation case, skip activation for system addresses
        if (
            _accounts[action.destination].activated == false
                && getTokenIndexFromSystemAddress(action.destination) > 10000
        ) {
            _chargeUSDCFee(sender);

            _accounts[action.destination].activated = true;

            _accounts[sender].spot[action.token] -= action._wei;
            _accounts[action.destination].spot[action.token] += _latentSpotBalance[sender][action.token] + action._wei;

            // this will no longer be needed
            _latentSpotBalance[sender][action.token] = 0;

            // officially init the destination account
            _initializedAccounts[action.destination] = true;
            _initializedSpotBalance[action.destination][action.token] = true;
            return;
        }

        address systemAddress = CoreWriterLib.getSystemAddress(action.token);

        _accounts[sender].spot[action.token] -= action._wei;

        if (action.destination != systemAddress) {
            _accounts[action.destination].spot[action.token] += action._wei;
        } else {
            uint256 transferAmount;
            if (action.token == HYPE_TOKEN_INDEX) {
                transferAmount = uint256(action._wei) * 1e10;
                deal(systemAddress, systemAddress.balance + transferAmount);
                vm.startPrank(systemAddress);
                (bool success,) = address(sender).call{value: transferAmount, gas: 30000}("");
                if (!success) {
                    revert("transfer failed");
                }
                return;
            }
            address evmContract = _tokens[action.token].evmContract;
            transferAmount = fromWei(action._wei, _tokens[action.token].evmExtraWeiDecimals);
            deal(evmContract, systemAddress, IERC20(evmContract).balanceOf(systemAddress) + transferAmount);
            vm.startPrank(systemAddress);
            IERC20(evmContract).safeTransfer(sender, transferAmount);
        }
    }

    function _chargeUSDCFee(address sender) internal {
        if (_accounts[sender].spot[USDC_TOKEN_INDEX] >= 1e8) {
            _accounts[sender].spot[USDC_TOKEN_INDEX] -= 1e8;
        } else if (_accounts[sender].perpBalance >= 1e8) {
            _accounts[sender].perpBalance -= 1e8;
        } else {
            revert("insufficient USDC balance for fee");
        }
    }

    function executeUsdClassTransfer(address sender, UsdClassTransferAction memory action)
        public
        initAccountWithToken(sender, USDC_TOKEN_INDEX)
        whenActivated(sender)
    {
        if (action.toPerp) {
            if (fromPerp(action.ntl) <= _accounts[sender].spot[USDC_TOKEN_INDEX]) {
                _accounts[sender].perpBalance += action.ntl;
                _accounts[sender].spot[USDC_TOKEN_INDEX] -= fromPerp(action.ntl);
            }
        } else {
            if (action.ntl <= _accounts[sender].perpBalance) {
                _accounts[sender].perpBalance -= action.ntl;
                _accounts[sender].spot[USDC_TOKEN_INDEX] += fromPerp(action.ntl);
            }
        }
    }

    function executeVaultTransfer(address sender, VaultTransferAction memory action)
        public
        initAccountWithVault(sender, action.vault)
        whenActivated(sender)
    {
        // first update their vault equity
        _accounts[sender].vaultEquity[action.vault].equity = readUserVaultEquity(sender, action.vault).equity;
        _userVaultMultiplier[sender][action.vault] = _vaultMultiplier[action.vault];

        if (action.isDeposit) {
            if (action.usd <= _accounts[sender].perpBalance) {
                _accounts[sender].vaultEquity[action.vault].equity += action.usd;
                _accounts[sender].vaultEquity[action.vault].lockedUntilTimestamp =
                    uint64((block.timestamp + 86400) * 1000);
                _accounts[sender].perpBalance -= action.usd;
                _vaultEquity[action.vault] += action.usd;
            } else {
                revert("insufficient balance");
            }
        } else {
            PrecompileLib.UserVaultEquity storage userVaultEquity = _accounts[sender].vaultEquity[action.vault];

            // a zero amount means withdraw the entire amount
            action.usd = action.usd == 0 ? userVaultEquity.equity : action.usd;

            // the vaults have a minimum withdraw of 1 / 100,000,000
            if (action.usd < _vaultEquity[action.vault] / 1e8) {
                revert("does not meet minimum withdraw");
            }

            if (action.usd <= userVaultEquity.equity && userVaultEquity.lockedUntilTimestamp / 1000 <= block.timestamp)
            {
                userVaultEquity.equity -= action.usd;
                _accounts[sender].perpBalance += action.usd;
            } else {
                revert("equity too low, or locked");
            }
        }
    }

    function executeStakingDeposit(address sender, StakingDepositAction memory action)
        public
        initAccountWithToken(sender, HYPE_TOKEN_INDEX)
        whenActivated(sender)
    {
        if (action._wei <= _accounts[sender].spot[HYPE_TOKEN_INDEX]) {
            _accounts[sender].spot[HYPE_TOKEN_INDEX] -= action._wei;
            _accounts[sender].staking += action._wei;
        }
    }

    function executeStakingWithdraw(address sender, StakingWithdrawAction memory action)
        public
        initAccountWithToken(sender, HYPE_TOKEN_INDEX)
        whenActivated(sender)
    {
        PrecompileLib.DelegatorSummary memory summary = readDelegatorSummary(sender);

        if (summary.nPendingWithdrawals >= 5) {
            revert("maximum of 5 pending withdrawals per account");
        }

        if (action._wei <= _accounts[sender].staking) {
            _accounts[sender].staking -= action._wei;

            WithdrawRequest memory withrawRequest = WithdrawRequest({
                account: sender, amount: action._wei, lockedUntilTimestamp: uint32(block.timestamp + 7 days)
            });

            _withdrawQueue.pushBack(serializeWithdrawRequest(withrawRequest));
        }
    }

    function executeTokenDelegate(address sender, TokenDelegateAction memory action)
        public
        initAccountWithToken(sender, HYPE_TOKEN_INDEX)
        whenActivated(sender)
    {
        if (_validators.length() != 0) {
            require(_validators.contains(action.validator));
        }

        // first update their delegation amount based on staking multiplier
        PrecompileLib.Delegation storage delegation = _accounts[sender].delegations[action.validator];
        delegation.amount = _getDelegationAmount(sender, action.validator);
        _userStakingYieldIndex[sender][action.validator] = _stakingYieldIndex;

        _accounts[sender].delegatedValidators.add(action.validator);

        if (action.isUndelegate) {
            if (action._wei <= delegation.amount && block.timestamp * 1000 > delegation.lockedUntilTimestamp) {
                _accounts[sender].staking += action._wei;
                delegation.amount -= action._wei;

                if (delegation.amount == 0) {
                    _accounts[sender].delegatedValidators.remove(action.validator);
                }
            } else {
                revert("Insufficient delegation amount OR Delegation is locked");
            }
        } else {
            if (action._wei <= _accounts[sender].staking) {
                _accounts[sender].staking -= action._wei;
                _accounts[sender].delegations[action.validator].amount += action._wei;

                _accounts[sender].delegations[action.validator].lockedUntilTimestamp =
                    ((block.timestamp + 86400) * 1000).toUint64();
            } else {
                revert("Insufficient staking balance");
            }
        }
    }

    function setMarkPx(uint32 perp, uint64 priceDiffBps, bool isIncrease) public {
        uint64 basePrice = readMarkPx(perp);
        if (isIncrease) {
            _perpMarkPrice[perp] = basePrice * (10000 + priceDiffBps) / 10000;
        } else {
            _perpMarkPrice[perp] = basePrice * (10000 - priceDiffBps) / 10000;
        }
    }

    function setMarkPx(uint32 perp, uint64 markPx) public {
        _perpMarkPrice[perp] = markPx;
    }

    function setSpotPx(uint32 spotMarketId, uint64 priceDiffBps, bool isIncrease) public {
        uint64 basePrice = readSpotPx(spotMarketId);
        if (isIncrease) {
            _spotPrice[spotMarketId] = basePrice * (10000 + priceDiffBps) / 10000;
        } else {
            _spotPrice[spotMarketId] = basePrice * (10000 - priceDiffBps) / 10000;
        }
    }

    function setSpotPx(uint32 spotMarketId, uint64 spotPx) public {
        _spotPrice[spotMarketId] = spotPx;
    }

    function isActionExecutable(LimitOrderAction memory action, uint64 px) internal pure returns (bool) {
        bool executable = action.isBuy ? action.limitPx >= px : action.limitPx <= px;
        return executable;
    }

    function setVaultMultiplier(address vault, uint256 multiplier) public {
        _vaultMultiplier[vault] = multiplier;
    }

    function setStakingYieldIndex(uint256 multiplier) public {
        _stakingYieldIndex = multiplier;
    }

    function processPendingOrders() public {
        for (uint256 i = _pendingOrders.length; i > 0; i--) {
            PendingOrder memory order = _pendingOrders[i - 1];
            uint32 spotMarketId = uint32(HLConversions.assetToSpotId(order.action.asset));
            PrecompileLib.SpotInfo memory spotInfo = PrecompileLib.spotInfo(spotMarketId);
            PrecompileLib.TokenInfo memory baseToken = _tokens[spotInfo.tokens[0]];
            uint64 spotPx = readSpotPx(spotMarketId) * SafeCast.toUint64(10 ** baseToken.szDecimals);

            if (isActionExecutable(order.action, spotPx)) {
                executeSpotLimitOrder(order.sender, order.action);

                // Remove executed order by swapping with last and popping
                _pendingOrders[i - 1] = _pendingOrders[_pendingOrders.length - 1];
                _pendingOrders.pop();
            }
        }
    }

    ////////// PERP LIQUIDATIONS ////////////////////
    function isLiquidatable(address user) public returns (bool) {
        uint64 totalNotional = 0;
        int64 totalUPnL = 0;
        uint64 totalLocked = 0;
        uint64 mmReq = 0;

        uint256 len = _userPerpPositions[user].length();

        for (uint256 i = len; i > 0; i--) {
            uint16 perpIndex = uint16(_userPerpPositions[user].at(i - 1));
            PrecompileLib.Position memory pos = _accounts[user].positions[perpIndex];
            if (pos.szi != 0) {
                uint64 markPx = readMarkPx(perpIndex);
                int64 szi = pos.szi;
                uint64 avgEntry = pos.entryNtl / abs(szi);
                int64 uPnL = szi * (int64(markPx) - int64(avgEntry));
                totalUPnL += uPnL;
                totalLocked += _accounts[user].margin[perpIndex];

                uint64 positionNotional = abs(szi) * markPx;
                totalNotional += positionNotional;

                // Per-perp maintenance margin requirement based on max leverage
                uint32 maxLev = _getMaxLeverage(perpIndex);
                uint64 mmBps = 5000 / maxLev; // 5000 / maxLev gives bps for mm_fraction = 0.5 / maxLev
                mmReq += (positionNotional * mmBps) / 10000;
            }
        }

        if (totalNotional == 0) {
            return false;
        }

        int64 equity = int64(_accounts[user].perpBalance) + int64(totalLocked) + totalUPnL;

        return equity < int64(mmReq);
    }

    function abs(int64 value) internal pure returns (uint64) {
        return value > 0 ? uint64(value) : uint64(-value);
    }

    function _getMaxLeverage(uint16 perpIndex) public view returns (uint32) {
        return _perpAssetInfo[perpIndex].maxLeverage;
    }

    // simplified liquidation, nukes all positions and resets the perp balance
    // for future: make this more realistic
    function _liquidateUser(address user) public {
        uint256 len = _userPerpPositions[user].length();
        for (uint256 i = len; i > 0; i--) {
            uint16 perpIndex = uint16(_userPerpPositions[user].at(i - 1));

            bytes32 key = _getKey(user, perpIndex);
            _openPerpPositions.remove(key);
            _accounts[user].positions[perpIndex].szi = 0;
            _accounts[user].positions[perpIndex].entryNtl = 0;
            _accounts[user].margin[perpIndex] = 0;
            _userPerpPositions[user].remove(perpIndex);
        }

        _accounts[user].perpBalance = 0;
    }

    function liquidatePositions() public {
        uint256 len = _openPerpPositions.length();

        if (len == 0) return;

        for (uint256 i = len; i > 0; i--) {
            bytes32 key = _openPerpPositions.at(i - 1);
            address user = address(uint160(uint256(key) >> 16));
            if (isLiquidatable(user)) {
                _liquidateUser(user);
            }
        }
    }
}
