// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { DoubleEndedQueue } from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import { Heap } from "@openzeppelin/contracts/utils/structs/Heap.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PrecompileLib} from "src/PrecompileLib.sol";
import {CoreWriterLib} from "src/CoreWriterLib.sol";


import { console } from "forge-std/console.sol";

import {RealL1Read} from "../../utils/RealL1Read.sol";

import {CoreView} from "./CoreView.sol";

uint64 constant KNOWN_TOKEN_USDC = 0;
uint64 constant KNOWN_TOKEN_HYPE = 150;


contract CoreExecution is CoreView {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Heap for Heap.Uint256Heap;

    using RealL1Read for *;



    function executeTokenTransfer(
      address,
      uint64 token,
      address from,
      uint256 value
    ) public payable initAccountWithToken(from, token) {
      if (_accounts[from].created) {
        _accounts[from].spot[token] += toWei(value, _tokens[token].evmExtraWeiDecimals);
      }
      else {
        _latentSpotBalance[from][token] += toWei(value, _tokens[token].evmExtraWeiDecimals);
      }
    }

    function executeNativeTransfer(address, address from, uint256 value) public payable initAccountWithToken(from, KNOWN_TOKEN_HYPE) {

      if (_accounts[from].created) {
        _accounts[from].spot[KNOWN_TOKEN_HYPE] += (value / 1e10).toUint64();
      }
      else {
        _latentSpotBalance[from][KNOWN_TOKEN_HYPE] += (value / 1e10).toUint64();
      }
    }

    // TODO:
    // - handle the other fields of the position
    // - handle isolated margin positions
    function executePerpLimitOrder(address sender, LimitOrderAction memory action) public initAccountWithPerp(sender, uint16(action.asset)) {
      uint16 perpIndex = uint16(action.asset);
      PrecompileLib.Position memory position = _accounts[sender].positions[perpIndex];

      bool isolated = position.isIsolated;

      uint256 markPx = PrecompileLib.markPx(perpIndex);


      if (!isolated) {
        if (action.isBuy) {
          if (markPx <= action.limitPx) {
            _executePerpLong(sender, action, markPx);
          }
        } 
        else {
          if (markPx >= action.limitPx) {
            _executePerpShort(sender, action, markPx);
          }
        }
      }

     
    }


        function _executePerpLong(address sender, LimitOrderAction memory action, uint256 markPx) internal {
      uint16 perpIndex = uint16(action.asset);

      // Check if there's an existing short position
      int64 szi = _accounts[sender].positions[perpIndex].szi;
      uint32 leverage = _accounts[sender].positions[perpIndex].leverage;

      if (szi < 0) {

        int64 newSzi = szi + int64(action.sz);

        if (newSzi <= 0) {
          // this means were reducing the short
          _accounts[sender].positions[perpIndex].szi += int64(action.sz);
          _accounts[sender].positions[perpIndex].entryNtl *= uint64(-newSzi) / uint64(-szi);
          _accounts[sender].perpBalance += action.sz * uint64(markPx) / leverage;
        }
        else {
          // this means were closing the short and opening a long

          uint64 oldMargin = _accounts[sender].positions[perpIndex].entryNtl / leverage;

          uint64 newMargin = uint64(newSzi) * uint64(markPx) / leverage;
          int64 marginDelta = int64(newMargin) - int64(oldMargin);
          

          _accounts[sender].positions[perpIndex].szi += int64(action.sz);
          _accounts[sender].positions[perpIndex].entryNtl = uint64(newSzi) * uint64(markPx);

          if (marginDelta > 0) {
            // we need more margin
            _accounts[sender].perpBalance -= uint64(marginDelta);
          }
          else {
            _accounts[sender].perpBalance += uint64(-marginDelta);
          }
        }
      } 
      else {
        console.log("increasing long position, @px=%e", markPx);
        // this means were just increasing the long position
        _accounts[sender].positions[perpIndex].szi += int64(action.sz);
        _accounts[sender].positions[perpIndex].entryNtl += uint64(action.sz) * uint64(markPx);

        _accounts[sender].perpBalance -= uint64(action.sz) * uint64(markPx) / leverage;
      }
    }

    function _executePerpShort(address sender, LimitOrderAction memory action, uint256 markPx) internal {
      uint16 perpIndex = uint16(action.asset);
      // check for an existing long position
      int64 szi = _accounts[sender].positions[perpIndex].szi;
      uint32 leverage = _accounts[sender].positions[perpIndex].leverage;

      if (szi <= 0) {
        // we are just increasing the short

        _accounts[sender].positions[perpIndex].szi -= int64(action.sz);
        _accounts[sender].positions[perpIndex].entryNtl += uint64(action.sz) * uint64(markPx);
        _accounts[sender].perpBalance -= uint64(action.sz) * uint64(markPx) / leverage;
        
      }
      else {
        int64 newSzi = szi - int64(action.sz);

        if (newSzi >= 0) {
          // we are reducing a long
          _accounts[sender].positions[perpIndex].szi -= int64(action.sz);
          _accounts[sender].positions[perpIndex].entryNtl *= uint64(newSzi) / uint64(szi);
          _accounts[sender].perpBalance += action.sz * uint64(markPx) / leverage;

        }
        else {
          // we are closing the long and opening a short

          uint64 oldMargin = _accounts[sender].positions[perpIndex].entryNtl / leverage;

          uint64 newMargin = uint64(-newSzi) * uint64(markPx) / leverage;
          int64 marginDelta = int64(newMargin) - int64(oldMargin);

          if (marginDelta > 0) {
            _accounts[sender].perpBalance -= uint64(marginDelta);
          }
          else {
            _accounts[sender].perpBalance += uint64(-marginDelta);
          }

          _accounts[sender].positions[perpIndex].szi -= int64(action.sz);
          _accounts[sender].positions[perpIndex].entryNtl = uint64(-newSzi) * uint64(markPx);
        }
      }
    }
    
    // basic simulation of spot trading, not accounting for orderbook depth, or fees
    function executeSpotLimitOrder(address sender, LimitOrderAction memory action) public initAccountWithSpotMarket(sender, action.asset - 10000) {

      // 1. find base/quote token
      // 2. find spot balance of the from token
      // 3. if enough, execute the order at the spot price (assume infinite depth)
      // 4. update their balances of the from and to token

      uint32 spotMarketId = action.asset - 1e4;

      PrecompileLib.SpotInfo memory spotInfo = RealL1Read.spotInfo(spotMarketId);

      uint64 spotPx = readSpotPx(spotMarketId);

      uint64 fromToken;
      uint64 toToken;

      bool executeNow = isActionExecutable(action, spotPx);

      if (executeNow) {
        console.log("EXECUTING ORDER!");
        if (action.isBuy) {
          fromToken = spotInfo.tokens[1];
          toToken = spotInfo.tokens[0];

          uint64 fromTokenAmount = action.sz * spotPx;

          if (_accounts[sender].spot[fromToken] >= fromTokenAmount) {
            _accounts[sender].spot[fromToken] -= fromTokenAmount;
            _accounts[sender].spot[toToken] += action.sz;
          }
          else {
            revert("insufficient balance");
          }
        }
        else {
          fromToken = spotInfo.tokens[0];
          toToken = spotInfo.tokens[1];

          uint64 fromTokenAmount = action.sz;

          if (_accounts[sender].spot[fromToken] >= fromTokenAmount) {
            _accounts[sender].spot[fromToken] -= fromTokenAmount;
            _accounts[sender].spot[toToken] += action.sz;
          }
          else {
            revert("insufficient balance");
          }
        }
      }
      else {
        console.log("order saved for later!");
        _pendingOrders.push(PendingOrder({
          sender: sender,
          action: action
        }));
      }

    }

 

    function executeSpotSend(
      address sender,
      SpotSendAction memory action
    ) internal whenAccountCreated(sender) initAccountWithToken(sender, action.token) initAccountWithToken(action.destination, action.token) {
      if (action._wei > _accounts[sender].spot[action.token]) {
        revert("insufficient balance");
      }
      
      // handle account activation case
      if (_accounts[action.destination].created == false) {

        _chargeUSDCFee(sender);

        _accounts[action.destination].created = true;
  
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
      }
      else {
        if (action.token == KNOWN_TOKEN_HYPE) {
          uint256 amount = action._wei * 1e10;
          deal(systemAddress, systemAddress.balance + amount);
          vm.prank(systemAddress);
          address(sender).call{value: amount, gas: 30000}("");
        }

        // TODO: this requires HYPE balance to pay some gas for the transfer
        address evmContract = _tokens[action.token].evmContract;
        uint256 amount = fromWei(action._wei, _tokens[action.token].evmExtraWeiDecimals);
        deal(evmContract, systemAddress, IERC20(evmContract).balanceOf(systemAddress) + amount);
        vm.prank(systemAddress);
        IERC20(evmContract).transfer(action.destination, amount);
      }

        
      }

    

    function _chargeUSDCFee(address sender) internal {
      if (_accounts[sender].spot[KNOWN_TOKEN_USDC] >= 1e8) {
        _accounts[sender].spot[KNOWN_TOKEN_USDC] -= 1e8;
      }
      else if (_accounts[sender].perpBalance >= 1e8) {
        _accounts[sender].perpBalance -= 1e8;
      }
      else {
        revert("insufficient USDC balance for fee");
      }
    }

    function executeUsdClassTransfer(
      address sender,
      UsdClassTransferAction memory action
    ) internal whenAccountCreated(sender) {
      if (action.toPerp) {
        if (fromPerp(action.ntl) <= _accounts[sender].spot[KNOWN_TOKEN_USDC]) {
          _accounts[sender].perpBalance += action.ntl;
          _accounts[sender].spot[KNOWN_TOKEN_USDC] -= fromPerp(action.ntl);
        }
      } else {
        if (action.ntl <= _accounts[sender].perpBalance) {
          _accounts[sender].perpBalance -= action.ntl;
          _accounts[sender].spot[KNOWN_TOKEN_USDC] += fromPerp(action.ntl);
        }
      }
    }

    function executeVaultTransfer(
      address sender,
      VaultTransferAction memory action
    ) internal whenAccountCreated(sender) {
      if (action.isDeposit) {
        if (action.usd <= _accounts[sender].perpBalance) {
          _accounts[sender].vaultEquity[action.vault].equity += action.usd;
          _accounts[sender].vaultEquity[action.vault].lockedUntilTimestamp = uint64((block.timestamp + 3600) * 1000);
          _accounts[sender].perpBalance -= action.usd;
          _vaultEquity[action.vault] += action.usd;
        }
        else {
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

        if (action.usd <= userVaultEquity.equity && userVaultEquity.lockedUntilTimestamp / 1000 <= block.timestamp) {
          userVaultEquity.equity -= action.usd;
          _accounts[sender].perpBalance += action.usd;
        }
        else {
          revert("equity too low, or locked");
        }
      }
    }

    function executeStakingDeposit(
      address sender,
      StakingDepositAction memory action
    ) internal whenAccountCreated(sender) {
      if (action._wei <= _accounts[sender].spot[KNOWN_TOKEN_HYPE]) {
        _accounts[sender].spot[KNOWN_TOKEN_HYPE] -= action._wei;
        _accounts[sender].staking += action._wei;
      }
    }

    function executeStakingWithdraw(
      address sender,
      StakingWithdrawAction memory action
    ) internal whenAccountCreated(sender) {
      if (action._wei <= _accounts[sender].staking) {
        _accounts[sender].staking -= action._wei;

        WithdrawRequest memory withrawRequest = WithdrawRequest({
          account: sender,
          amount: action._wei,
          lockedUntilTimestamp: uint32(block.timestamp + 7 days)
        });

        _withdrawQueue.pushBack(serializeWithdrawRequest(withrawRequest));
      }
    }

    function executeTokenDelegate(address sender, TokenDelegateAction memory action) internal {
      require(_validators.contains(action.validator));

      if (action.isUndelegate) {
        PrecompileLib.Delegation storage delegation = _accounts[sender].delegations[action.validator];
        if (action._wei <= delegation.amount && block.timestamp * 1000 > delegation.lockedUntilTimestamp) {
          _accounts[sender].staking += action._wei;
          delegation.amount -= action._wei;
        }
      } else {
        if (action._wei <= _accounts[sender].staking) {
          _accounts[sender].staking -= action._wei;
          _accounts[sender].delegations[action.validator].amount += action._wei;
          _accounts[sender].delegations[action.validator].lockedUntilTimestamp = ((block.timestamp + 84600) * 1000)
            .toUint64();
        }
      }
    }

    function setMarkPx(uint32 perp, uint64 priceDiffBps, bool isIncrease) public {
      uint64 basePrice = readMarkPx(perp);
      if (isIncrease) {
        _perpMarkPrice[perp] = basePrice * (10000 + priceDiffBps) / 10000;
      }
      else {
        _perpMarkPrice[perp] = basePrice * (10000 - priceDiffBps) / 10000;
      }
    }

    function setMarkPx(uint32 perp, uint64 markPx) public {
      _perpMarkPrice[perp] = markPx;
    }
    
    function setSpotPx(uint32 spotMarketId, uint64 spotPx) public {
      _spotPrice[spotMarketId] = spotPx;
    }


    function isActionExecutable(LimitOrderAction memory action, uint64 px) internal pure returns (bool) {
      bool executable = action.isBuy ? action.limitPx >= px : action.limitPx <= px;
      return executable;
    }
    
    function processPendingOrders() public {
      for (uint256 i = _pendingOrders.length; i > 0; i--) {
        PendingOrder memory order = _pendingOrders[i - 1];
        uint32 spotMarketId = order.action.asset - 1e4;
        uint64 spotPx = readSpotPx(spotMarketId);
        
        if (isActionExecutable(order.action, spotPx)) {
          executeSpotLimitOrder(order.sender, order.action);
          
          // Remove executed order by swapping with last and popping
          _pendingOrders[i - 1] = _pendingOrders[_pendingOrders.length - 1];
          _pendingOrders.pop();
        }
      }
    }



    
}
