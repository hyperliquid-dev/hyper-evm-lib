// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { DoubleEndedQueue } from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import { Heap } from "@openzeppelin/contracts/utils/structs/Heap.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PrecompileLib} from "src/PrecompileLib.sol";
import {HLConstants} from "src/CoreWriterLib.sol";
import { console } from "forge-std/console.sol";

import {RealL1Read} from "../utils/RealL1Read.sol";
import {StdCheats, Vm} from "forge-std/StdCheats.sol";

uint64 constant KNOWN_TOKEN_USDC = 0;
uint64 constant KNOWN_TOKEN_HYPE = 150;


/// Modified from https://github.com/ambitlabsxyz/hypercore
contract HyperCoreState is StdCheats {
    using Address for address payable;
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Heap for Heap.Uint256Heap;

    using RealL1Read for *;

    mapping(uint64 token => PrecompileLib.TokenInfo) private _tokens;

    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);


    struct WithdrawRequest {
      address account;
      uint64 amount;
      uint32 lockedUntilTimestamp;
    }

    struct AccountData {
      bool created;
      uint64 perp;
      mapping(uint64 => uint64) spot;
      mapping(address vault => PrecompileLib.UserVaultEquity) vaultEquity;
      uint64 staking;
      mapping(address validator => PrecompileLib.Delegation) delegations;
      mapping(uint16 perpIndex => PrecompileLib.Position) positions;
    }

    mapping(address account => AccountData) private _accounts;
    mapping(address account => bool initialized) private _initializedAccounts;
    mapping(address account => mapping(uint64 token => bool initialized)) private _initializedSpotBalance;
    mapping(address account => mapping(address vault => bool initialized)) private _initializedVaults;

    mapping(address account => mapping(uint32 perpIndex => uint64 markPrice)) private _perpMarkPrice;
    mapping(address account => mapping(uint32 spotMarketId => uint64 spotPrice)) private _spotPrice;

    mapping(address vault => uint64) private _vaultEquity;

    DoubleEndedQueue.Bytes32Deque private _withdrawQueue;
    
    struct PendingOrder {
        address sender;
        LimitOrderAction action;
    }
    
    PendingOrder[] private _pendingOrders;

    EnumerableSet.AddressSet private _validators;

    /////////////////////////
    /// STATE INITIALIZERS///
    /////////////////////////

    modifier initAccountWithToken(address _account, uint64 token) {

      if (!_initializedSpotBalance[_account][token]) {

        registerTokenInfo(token);
        _initializeAccountWithToken(_account, token);
      }
      _;
    }

    modifier initAccountWithSpotMarket(address _account, uint32 spotMarketId) {

      uint64 baseToken = PrecompileLib.spotInfo(spotMarketId).tokens[0];
      uint64 quoteToken = PrecompileLib.spotInfo(spotMarketId).tokens[1];

      if (!_initializedSpotBalance[_account][baseToken] ) {

        registerTokenInfo(baseToken);
        _initializeAccountWithToken(_account, baseToken);
      }

      if (!_initializedSpotBalance[_account][quoteToken]) {
        registerTokenInfo(quoteToken);
        _initializeAccountWithToken(_account, quoteToken);
      }

      _;
    }

    modifier initAccountWithVault(address _account, address _vault) {
      if (!_initializedVaults[_account][_vault]) {
        _initializeAccount(_account);
        _initializeAccountWithVault(_account, _vault);
      }
      _;
    }

    modifier initAccountWithPerp(address _account, uint16 perp) {
      if (_perpMarkPrice[_account][perp] == 0) {
        _initializeAccount(_account);
        _initializeAccountWithPerp(_account, perp);
      }
      _;
    }

    modifier initAccount(address _account) {
      if (!_initializedAccounts[_account]) {
        _initializeAccount(_account);
      }
      _;
    }

    function _initializeAccountWithToken(address _account, uint64 token) internal {
      _initializeAccount(_account);

      if (_accounts[_account].created == false) {
        return;
      }

      _initializedSpotBalance[_account][token] = true;
      _accounts[_account].spot[token] = RealL1Read.spotBalance(_account, token).total;
    }

    function _initializeAccountWithVault(address _account, address _vault) internal {
      _initializedVaults[_account][_vault] = true;
      _accounts[_account].vaultEquity[_vault] = RealL1Read.userVaultEquity(_account, _vault);
    }

    function _initializeAccountWithPerp(address _account, uint16 perp) internal {
      _perpMarkPrice[_account][perp] = RealL1Read.markPx(perp);
      _accounts[_account].positions[perp] = RealL1Read.position(_account, perp);
    }

    function _initializeAccount(address _account) internal {
      bool initialized = _initializedAccounts[_account];

      if (initialized) {
        return;
      }

      AccountData storage account = _accounts[_account];

      // check if the acc is created on Core
      RealL1Read.CoreUserExists memory coreUserExists = RealL1Read.coreUserExists(_account);
      if (!coreUserExists.exists) {
        return;
      }

      _initializedAccounts[_account] = true;
      account.created = true;


      // setting perp balance
      account.perp = RealL1Read.withdrawable(_account).withdrawable;
      

      // setting staking balance
      PrecompileLib.DelegatorSummary memory summary = RealL1Read.delegatorSummary(_account);
      account.staking = summary.undelegated;
      // TODO: need to track the pending withdrawals, and have a way to credit them later

      // set delegations
      PrecompileLib.Delegation[] memory delegations = RealL1Read.delegations(_account);
      for (uint256 i = 0; i < delegations.length; i++) {
        account.delegations[delegations[i].validator] = delegations[i];
      }
    }

    receive() external payable {}

    modifier whenAccountCreated(address sender) {
      if (_accounts[sender].created == false) {
        return;
      }
      _;
    }

    function registerTokenInfo(uint64 index) public {

      // if the token is already registered, return early
      if (bytes(_tokens[index].name).length > 0) {
        return;
      }

      PrecompileLib.TokenInfo memory tokenInfo = RealL1Read.tokenInfo(uint32(index));

      // this means that the precompile call failed
      if (tokenInfo.evmContract == RealL1Read.INVALID_ADDRESS) return;
      _tokens[index] = tokenInfo;
    }

    function registerValidator(address validator) public {
      _validators.add(validator);
    }

    /// @dev account creation can be forced when there isnt a reliance on testing that workflow.
    function forceAccountCreation(address account) public {
      _accounts[account].created = true;
    }

    // TODO: maybe have a flag that indicates to just always return true
    function coreUserExists(address account) public initAccount(account) returns (bool) {
      return _accounts[account].created;
    }

    function forceSpot(address account, uint64 token, uint64 _wei) public payable initAccountWithToken(account, token) {
      _accounts[account].spot[token] = _wei;
    }

    function forcePerp(address account, uint64 usd) public payable {
      forceAccountCreation(account);
      _accounts[account].perp = usd;
    }

    function forceStaking(address account, uint64 _wei) public payable {
      forceAccountCreation(account);
      _accounts[account].staking = _wei;
    }

    function forceDelegation(address account, address validator, uint64 amount, uint64 lockedUntilTimestamp) public {
      forceAccountCreation(account);
      _accounts[account].delegations[validator] = PrecompileLib.Delegation({
        validator: validator,
        amount: amount,
        lockedUntilTimestamp: lockedUntilTimestamp
      });
    }

    function forceVaultEquity(address account, address vault, uint64 usd, uint64 lockedUntilTimestamp) public payable {
      forceAccountCreation(account);

      _vaultEquity[vault] -= _accounts[account].vaultEquity[vault].equity;
      _vaultEquity[vault] += usd;

      _accounts[account].vaultEquity[vault].equity = usd;
      _accounts[account].vaultEquity[vault].lockedUntilTimestamp = lockedUntilTimestamp > 0
        ? lockedUntilTimestamp
        : uint64((block.timestamp + 3600) * 1000);
    }

    function tokenExists(uint64 token) private view returns (bool) {
      return bytes(_tokens[token].name).length > 0;
    }

    /// @dev unstaking takes 7 days and after which it will automatically appear in the users
    /// spot balance so we need to check this at the end of each operation to simulate that.
    function flushCWithdrawQueue() public {
      while (_withdrawQueue.length() > 0) {
        WithdrawRequest memory request = deserializeWithdrawRequest(_withdrawQueue.front());

        if (request.lockedUntilTimestamp > block.timestamp) {
          break;
        }

        _withdrawQueue.popFront();

        _accounts[request.account].spot[KNOWN_TOKEN_HYPE] += request.amount;
      }
    }

    function executeTokenTransfer(
      address,
      uint64 token,
      address from,
      uint256 value
    ) public payable whenAccountCreated(from) initAccountWithToken(from, token) {
      _accounts[from].spot[token] += toWei(value, _tokens[token].evmExtraWeiDecimals);
    }

    //TODO: currently if accountCreated==false, then it wont increment balance. but then even once its activated, the funds are lost. instead- the funds should be simply hidden and unusable until the account is created.
    //@i have a new mapping for waiting balances, which is set to the real balance once the account is created
    function executeNativeTransfer(address, address from, uint256 value) public payable whenAccountCreated(from) initAccountWithToken(from, KNOWN_TOKEN_HYPE) {
      _accounts[from].spot[KNOWN_TOKEN_HYPE] += (value / 1e10).toUint64();
    }

    function executeRawAction(address sender, uint24 kind, bytes calldata data) public payable {
      if (kind == HLConstants.LIMIT_ORDER_ACTION) {
        LimitOrderAction memory action = abi.decode(data, (LimitOrderAction));

        // for perps (check that the ID is not a spot asset ID
        if (action.asset < 1e4 || action.asset > 1e5) {
          executePerpLimitOrder(sender, action);
        }
        else {
          executeSpotLimitOrder(sender, action);
        }
        return;
      }

      if (kind == HLConstants.VAULT_TRANSFER_ACTION) {
        executeVaultTransfer(sender, abi.decode(data, (VaultTransferAction)));
        return;
      }

      if (kind == HLConstants.TOKEN_DELEGATE_ACTION) {
        executeTokenDelegate(sender, abi.decode(data, (TokenDelegateAction)));
        return;
      }

      if (kind == HLConstants.STAKING_DEPOSIT_ACTION) {
        executeStakingDeposit(sender, abi.decode(data, (StakingDepositAction)));
        return;
      }

      if (kind == HLConstants.STAKING_WITHDRAW_ACTION) {
        executeStakingWithdraw(sender, abi.decode(data, (StakingWithdrawAction)));
        return;
      }

      if (kind == HLConstants.SPOT_SEND_ACTION) {
        executeSpotSend(sender, abi.decode(data, (SpotSendAction)));
        return;
      }

      if (kind == HLConstants.USD_CLASS_TRANSFER_ACTION) {
        executeUsdClassTransfer(sender, abi.decode(data, (UsdClassTransferAction)));
        return;
      }
    }
    

    // TODO:
    // - split into helper functions
    // - handle the other fields of the position
    // - handle isolated margin positions
    // - handle the case where the account is not created
    function executePerpLimitOrder(address sender, LimitOrderAction memory action) public initAccountWithPerp(sender, uint16(action.asset)) {
      uint16 perpIndex = uint16(action.asset);
      uint256 markPx = PrecompileLib.markPx(perpIndex);

      if (action.isBuy) {
        if (markPx <= action.limitPx) {
          // Check if there's an existing short position
          int64 szi = _accounts[sender].positions[perpIndex].szi;
          uint32 leverage = _accounts[sender].positions[perpIndex].leverage;

          if (szi < 0) {

            int64 newSzi = szi + int64(action.sz);

            if (newSzi <= 0) {
              // this means were reducing the short
              _accounts[sender].positions[perpIndex].szi += int64(action.sz);
              _accounts[sender].positions[perpIndex].entryNtl *= uint64(-newSzi) / uint64(-szi);
              _accounts[sender].perp += action.sz * uint64(markPx) / leverage;
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
                _accounts[sender].perp -= uint64(marginDelta);
              }
              else {
                _accounts[sender].perp += uint64(-marginDelta);
              }
            }
          } 
          else {
            console.log("increasing long position, @px=%e", markPx);
            // this means were just increasing the long position
            _accounts[sender].positions[perpIndex].szi += int64(action.sz);
            _accounts[sender].positions[perpIndex].entryNtl += uint64(action.sz) * uint64(markPx);

            _accounts[sender].perp -= uint64(action.sz) * uint64(markPx) / leverage;
          }
        }
      } 
      else {
        if (markPx >= action.limitPx) {
          // check for an existing long position
          int64 szi = _accounts[sender].positions[perpIndex].szi;
          uint32 leverage = _accounts[sender].positions[perpIndex].leverage;

          if (szi <= 0) {
            // we are just increasing the short

            _accounts[sender].positions[perpIndex].szi -= int64(action.sz);
            _accounts[sender].positions[perpIndex].entryNtl += uint64(action.sz) * uint64(markPx);
            _accounts[sender].perp -= uint64(action.sz) * uint64(markPx) / leverage;
            
          }
          else {
            
            int64 newSzi = szi - int64(action.sz);

            if (newSzi >= 0) {
              // we are reducing a long
              _accounts[sender].positions[perpIndex].szi -= int64(action.sz);
              _accounts[sender].positions[perpIndex].entryNtl *= uint64(newSzi) / uint64(szi);
              _accounts[sender].perp += action.sz * uint64(markPx) / leverage;

            }
            else {
              // we are closing the long and opening a short

              uint64 oldMargin = _accounts[sender].positions[perpIndex].entryNtl / leverage;

              uint64 newMargin = uint64(-newSzi) * uint64(markPx) / leverage;
              int64 marginDelta = int64(newMargin) - int64(oldMargin);

              if (marginDelta > 0) {
                _accounts[sender].perp -= uint64(marginDelta);
              }
              else {
                _accounts[sender].perp += uint64(-marginDelta);
              }

              _accounts[sender].positions[perpIndex].szi -= int64(action.sz);
              _accounts[sender].positions[perpIndex].entryNtl = uint64(-newSzi) * uint64(markPx);
            }
          }
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
        console.log("ORDER GOING TO PENDING!");
        _pendingOrders.push(PendingOrder({
          sender: sender,
          action: action
        }));
      }

    }

    function executeSpotSend(
      address sender,
      SpotSendAction memory action
    ) private whenAccountCreated(sender) initAccountWithToken(sender, action.token) initAccountWithToken(action.destination, action.token) {
      if (action._wei > _accounts[sender].spot[action.token]) {
        return;
      }

      if (action.token == KNOWN_TOKEN_USDC &&_accounts[action.destination].created == false) {

        if (action._wei > _accounts[sender].spot[action.token] - 1e8) {
        return;
        } else {
          _accounts[sender].spot[action.token] -= action._wei + 1e8;
          _accounts[action.destination].spot[action.token] += action._wei;
          _accounts[action.destination].created = true;
          return;
        }
      }
      

      _accounts[sender].spot[action.token] -= action._wei;

      address systemAddress = action.token == 150
        ? 0x2222222222222222222222222222222222222222
        : address(uint160(address(0x2000000000000000000000000000000000000000)) + action.token);

      if (action.destination == systemAddress) {

        if (action.token == KNOWN_TOKEN_HYPE) {
          uint256 amount = action._wei * 1e10;
          deal(systemAddress, systemAddress.balance + amount);
          vm.prank(systemAddress);
          payable(sender).sendValue(amount);
          return;
        }

        // TODO: this requires HYPE balance to pay some gas for the transfer
        address evmContract = _tokens[action.token].evmContract;
        uint256 amount = fromWei(action._wei, _tokens[action.token].evmExtraWeiDecimals);
        deal(evmContract, systemAddress, IERC20(evmContract).balanceOf(systemAddress) + amount);
        vm.prank(systemAddress);
        IERC20(evmContract).transfer(action.destination, amount);
        return;
      }

      _accounts[action.destination].spot[action.token] += action._wei;
    }

    function executeUsdClassTransfer(
      address sender,
      UsdClassTransferAction memory action
    ) private whenAccountCreated(sender) {
      if (action.toPerp) {
        if (fromPerp(action.ntl) <= _accounts[sender].spot[KNOWN_TOKEN_USDC]) {
          _accounts[sender].perp += action.ntl;
          _accounts[sender].spot[KNOWN_TOKEN_USDC] -= fromPerp(action.ntl);
        }
      } else {
        if (action.ntl <= _accounts[sender].perp) {
          _accounts[sender].perp -= action.ntl;
          _accounts[sender].spot[KNOWN_TOKEN_USDC] += fromPerp(action.ntl);
        }
      }
    }

    function executeVaultTransfer(
      address sender,
      VaultTransferAction memory action
    ) private whenAccountCreated(sender) {
      if (action.isDeposit) {
        if (action.usd <= _accounts[sender].perp) {
          _accounts[sender].vaultEquity[action.vault].equity += action.usd;
          _accounts[sender].vaultEquity[action.vault].lockedUntilTimestamp = uint64((block.timestamp + 3600) * 1000);
          _accounts[sender].perp -= action.usd;
          _vaultEquity[action.vault] += action.usd;
        }
      } else {
        PrecompileLib.UserVaultEquity storage userVaultEquity = _accounts[sender].vaultEquity[action.vault];

        // a zero amount means withdraw the entire amount
        action.usd = action.usd == 0 ? userVaultEquity.equity : action.usd;

        // the vaults have a minimum withdraw of 1 / 100,000,000
        if (action.usd < _vaultEquity[action.vault] / 1e8) {
          return;
        }

        if (action.usd <= userVaultEquity.equity && userVaultEquity.lockedUntilTimestamp / 1000 <= block.timestamp) {
          userVaultEquity.equity -= action.usd;
          _accounts[sender].perp += action.usd;
        }
      }
    }

    function executeStakingDeposit(
      address sender,
      StakingDepositAction memory action
    ) private whenAccountCreated(sender) {
      if (action._wei <= _accounts[sender].spot[KNOWN_TOKEN_HYPE]) {
        _accounts[sender].spot[KNOWN_TOKEN_HYPE] -= action._wei;
        _accounts[sender].staking += action._wei;
      }
    }

    function executeStakingWithdraw(
      address sender,
      StakingWithdrawAction memory action
    ) private whenAccountCreated(sender) {
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

    function executeTokenDelegate(address sender, TokenDelegateAction memory action) private {
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

    function readTokenInfo(uint32 token) public view returns (PrecompileLib.TokenInfo memory) {
      require(tokenExists(token));
      return _tokens[token];
    }

    function setMarkPx(uint32 perp, uint64 priceDiffBps, bool isIncrease) public {
      uint64 basePrice = readMarkPx(perp);
      if (isIncrease) {
        _perpMarkPrice[msg.sender][perp] = basePrice * (10000 + priceDiffBps) / 10000;
      }
      else {
        _perpMarkPrice[msg.sender][perp] = basePrice * (10000 - priceDiffBps) / 10000;
      }
    }

    function setMarkPx(uint32 perp, uint64 markPx) public {
      _perpMarkPrice[msg.sender][perp] = markPx;
    }
    
    function setSpotPx(uint32 spotMarketId, uint64 spotPx) public {
      _spotPrice[msg.sender][spotMarketId] = spotPx;
    }

    function readMarkPx(uint32 perp) public returns (uint64) {

      if (_perpMarkPrice[msg.sender][perp] == 0) {
        return RealL1Read.markPx(perp);
      }

      return _perpMarkPrice[msg.sender][perp];
    }
    
    function readSpotPx(uint32 spotMarketId) public returns (uint64) {
      if (_spotPrice[msg.sender][spotMarketId] == 0) {
        return PrecompileLib.spotPx(spotMarketId);
      }
      
      return _spotPrice[msg.sender][spotMarketId];
    }
    
    function readSpotBalance(address account, uint64 token) public returns (PrecompileLib.SpotBalance memory) {
      
      if (_initializedSpotBalance[account][token] == false) {
        return RealL1Read.spotBalance(account, token);
      }

      return PrecompileLib.SpotBalance({ total: _accounts[account].spot[token], entryNtl: 0, hold: 0 });
    }

    // Even if the HyperCore account is not created, the precompile returns 0 (it does not revert)
    //TODO: remove the modifier and instead use RealL1Read if the account is not initialized. (ensures that the function can be a view function, callable via L1Read)
    function readWithdrawable(address account) public initAccount(account) returns (PrecompileLib.Withdrawable memory) {
      return PrecompileLib.Withdrawable({ withdrawable: _accounts[account].perp });
    }

    function readUserVaultEquity(address user, address vault) public view returns (PrecompileLib.UserVaultEquity memory) {
      return _accounts[user].vaultEquity[vault];
    }

    function readDelegation(
      address user,
      address validator
    ) public view returns (PrecompileLib.Delegation memory delegation) {
      delegation.validator = validator;
      delegation.amount = _accounts[user].delegations[validator].amount;
      delegation.lockedUntilTimestamp = _accounts[user].delegations[validator].lockedUntilTimestamp;
    }

    function readDelegations(address user) public view returns (PrecompileLib.Delegation[] memory userDelegations) {
      address[] memory validators = _validators.values();

      userDelegations = new PrecompileLib.Delegation[](validators.length);
      for (uint256 i; i < userDelegations.length; i++) {
        userDelegations[i].validator = validators[i];

        PrecompileLib.Delegation memory delegation = _accounts[user].delegations[validators[i]];
        userDelegations[i].amount = delegation.amount;
        userDelegations[i].lockedUntilTimestamp = delegation.lockedUntilTimestamp;
      }
    }

    function readDelegatorSummary(address user) public view returns (PrecompileLib.DelegatorSummary memory summary) {
      address[] memory validators = _validators.values();

      for (uint256 i; i < validators.length; i++) {
        PrecompileLib.Delegation memory delegation = _accounts[user].delegations[validators[i]];
        summary.delegated += delegation.amount;
      }

      summary.undelegated = _accounts[user].staking;

      for (uint256 i; i < _withdrawQueue.length(); i++) {
        WithdrawRequest memory request = deserializeWithdrawRequest(_withdrawQueue.at(i));
        if (request.account == user) {
          summary.nPendingWithdrawals++;
          summary.totalPendingWithdrawal += request.amount;
        }
      }
    }

    function readPosition(address user, uint16 perp) public view returns (PrecompileLib.Position memory) {
      return _accounts[user].positions[perp];
    }


    function isActionExecutable(LimitOrderAction memory action, uint64 px) private pure returns (bool) {
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

    //////// conversions ////////

    function toWei(uint256 amount, int8 evmExtraWeiDecimals) private pure returns (uint64) {
      uint256 _wei = evmExtraWeiDecimals == 0 ? amount : evmExtraWeiDecimals > 0
        ? amount / 10 ** uint8(evmExtraWeiDecimals)
        : amount * 10 ** uint8(-evmExtraWeiDecimals);

      return _wei.toUint64();
    }

    function fromWei(uint64 _wei, int8 evmExtraWeiDecimals) private pure returns (uint256) {
      return
        evmExtraWeiDecimals == 0 ? _wei : evmExtraWeiDecimals > 0
          ? _wei * 10 ** uint8(evmExtraWeiDecimals)
          : _wei / 10 ** uint8(-evmExtraWeiDecimals);
    }

    function fromPerp(uint64 usd) private pure returns (uint64) {
      return usd * 1e2;
    }


    // converting a withdraw request into a bytes32
    function serializeWithdrawRequest(HyperCoreState.WithdrawRequest memory request) internal pure returns (bytes32) {
      return
        bytes32(
          (uint256(uint160(request.account)) << 96) |
            (uint256(request.amount) << 32) |
            uint40(request.lockedUntilTimestamp)
        );
    }

    function deserializeWithdrawRequest(bytes32 data) internal pure returns (HyperCoreState.WithdrawRequest memory request) {
      request.account = address(uint160(uint256(data) >> 96));
      request.amount = uint64(uint256(data) >> 32);
      request.lockedUntilTimestamp = uint32(uint256(data));
    }


    struct LimitOrderAction {
      uint32 asset;
      bool isBuy;
      uint64 limitPx;
      uint64 sz;
      bool reduceOnly;
      uint8 encodedTif;
      uint128 cloid;
    }

    struct VaultTransferAction {
      address vault;
      bool isDeposit;
      uint64 usd;
    }

    struct TokenDelegateAction {
      address validator;
      uint64 _wei;
      bool isUndelegate;
    }

    struct StakingDepositAction {
      uint64 _wei;
    }

    struct StakingWithdrawAction {
      uint64 _wei;
    }

    struct SpotSendAction {
      address destination;
      uint64 token;
      uint64 _wei;
    }

    struct UsdClassTransferAction {
      uint64 ntl;
      bool toPerp;
    }
}
